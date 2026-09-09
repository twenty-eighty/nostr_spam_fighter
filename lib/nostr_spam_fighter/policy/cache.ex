defmodule NostrSpamFighter.Policy.Cache do
  @moduledoc """
  Compact ETS policy cache keyed by **registrable domain** (eTLD+1).

  Host and domain blocklist entries are collapsed to their registrable domain at
  compile time. Matching a hostname then needs a single O(1) lookup: if
  `ads.evil.com` is checked, we look up `evil.com`. Subdomains inherit the
  domain owner's listing.

  Stored values are slim tuples (no duplicated domain string / slug maps) and
  the table is `:compressed` to fit large adult lists in ~512MB instances.
  """

  use GenServer

  alias NostrSpamFighter.Policy.PublicSuffix

  @meta :nsf_policy_meta
  @retire_ms 5_000
  @boot_rebuild_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@meta, [:named_table, :set, :public, read_concurrency: true])
    domains = new_domains_table()
    :ets.insert(@meta, {:domains, domains})
    :ets.insert(@meta, {:generation, 0})
    :ets.insert(@meta, {:ready, true})
    {:ok, %{boot_rebuild_ref: nil}, {:continue, :schedule_boot_rebuild}}
  end

  @impl true
  def handle_continue(:schedule_boot_rebuild, state) do
    ref = Process.send_after(self(), :boot_rebuild, @boot_rebuild_ms)
    {:noreply, %{state | boot_rebuild_ref: ref}}
  end

  @impl true
  def handle_info(:boot_rebuild, state) do
    unless Application.get_env(:nostr_spam_fighter, :ingest_enabled, true) == false do
      _ = NostrSpamFighter.Policy.Compiler.compile()
    end

    {:noreply, %{state | boot_rebuild_ref: nil}}
  end

  def handle_info({:retire_tables, domains}, state) do
    delete_table(domains)
    {:noreply, state}
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    state = cancel_boot_rebuild(state)
    result = NostrSpamFighter.Policy.Compiler.compile()
    {:reply, result, state}
  end

  def handle_call({:install, generation, domains}, _from, state) do
    state = cancel_boot_rebuild(state)
    do_install(generation, domains)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:compiled, _result}, state), do: {:noreply, state}

  @spec generation() :: non_neg_integer()
  def generation do
    case :ets.lookup(@meta, :generation) do
      [{:generation, gen}] -> gen
      _ -> 0
    end
  end

  @spec ready?() :: boolean()
  def ready? do
    case :ets.lookup(@meta, :ready) do
      [{:ready, true}] -> true
      _ -> false
    end
  end

  @doc """
  Returns match maps for a registrable domain key.
  """
  @spec lookup_domain(String.t()) :: [map()]
  def lookup_domain(domain) when is_binary(domain) do
    lookup_domain(domain, 1)
  end

  def lookup_domain(_), do: []

  @spec size() :: non_neg_integer()
  def size, do: table_size(domains_table())

  @spec rebuild() :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :rebuild, 120_000)
    else
      NostrSpamFighter.Policy.Compiler.compile()
    end
  end

  @doc false
  @spec install(non_neg_integer(), :ets.tid()) :: :ok
  def install(generation, domains) when is_integer(generation) and generation >= 0 do
    if self() == Process.whereis(__MODULE__) do
      do_install(generation, domains)
    else
      GenServer.call(__MODULE__, {:install, generation, domains})
    end
  end

  @doc false
  @spec new_domains_table() :: :ets.tid()
  def new_domains_table do
    :ets.new(:nsf_policy_domains, [
      :public,
      :set,
      :compressed,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  @doc false
  def insert_rule(domains, rule) do
    case rule.rule_type do
      type when type in ["host", "domain"] ->
        case PublicSuffix.registrable_domain(rule.normalized_value) do
          domain when is_binary(domain) and domain != "" ->
            hit =
              {rule.category_id, rule.blocklist_id, rule.blocklist_version_id, rule.entry_id}

            case :ets.lookup(domains, domain) do
              [{^domain, hits}] ->
                if Enum.any?(hits, fn {category_id, _, _, _} ->
                     category_id == rule.category_id
                   end) do
                  true
                else
                  :ets.insert(domains, {domain, [hit | hits]})
                end

              [] ->
                :ets.insert(domains, {domain, [hit]})
            end

          _ ->
            false
        end

      # URL-prefix rules are intentionally ignored to keep the hot cache small.
      _ ->
        false
    end
  end

  defp lookup_domain(domain, retries) do
    case domains_table() do
      nil ->
        []

      tid ->
        try do
          case :ets.lookup(tid, domain) do
            [{^domain, hits}] ->
              Enum.map(hits, fn {category_id, blocklist_id, version_id, entry_id} ->
                %{
                  entry_id: entry_id,
                  rule_type: "domain",
                  normalized_value: domain,
                  blocklist_id: blocklist_id,
                  blocklist_version_id: version_id,
                  category_id: category_id
                }
              end)

            _ ->
              []
          end
        rescue
          ArgumentError ->
            if retries > 0, do: lookup_domain(domain, retries - 1), else: []
        end
    end
  end

  defp cancel_boot_rebuild(%{boot_rebuild_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | boot_rebuild_ref: nil}
  end

  defp cancel_boot_rebuild(state), do: state

  defp do_install(generation, domains) do
    old = domains_table()
    :ets.insert(@meta, {:domains, domains})
    :ets.insert(@meta, {:generation, generation})
    :ets.insert(@meta, {:ready, true})
    schedule_retire(old)
    :ok
  end

  defp schedule_retire(domains) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        Process.send_after(pid, {:retire_tables, domains}, @retire_ms)

      _ ->
        delete_table(domains)
    end
  end

  defp domains_table do
    case :ets.lookup(@meta, :domains) do
      [{:domains, tid}] -> tid
      _ -> nil
    end
  end

  defp table_size(nil), do: 0

  defp table_size(tid) do
    :ets.info(tid, :size) || 0
  rescue
    ArgumentError -> 0
  end

  defp delete_table(nil), do: :ok

  defp delete_table(tid) do
    if :ets.info(tid) != :undefined, do: :ets.delete(tid)
  rescue
    ArgumentError -> :ok
  end
end
