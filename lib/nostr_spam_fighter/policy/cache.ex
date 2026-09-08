defmodule NostrSpamFighter.Policy.Cache do
  @moduledoc """
  ETS-backed compiled policy keyed for O(1) host/domain lookups.

  PostgreSQL remains authoritative. Rules are stored as:
  - host/domain bag keyed by `{rule_type, normalized_value}`
  - url_prefix bag keyed by `normalized_value` (scanned; typically small)
  """

  use GenServer

  @meta :nsf_policy_meta
  @retire_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@meta, [:named_table, :set, :public, read_concurrency: true])
    {host_domain, url} = new_tables()
    :ets.insert(@meta, {:host_domain, host_domain})
    :ets.insert(@meta, {:url_prefix, url})
    :ets.insert(@meta, {:generation, 0})
    :ets.insert(@meta, {:ready, false})
    {:ok, %{}, {:continue, :rebuild}}
  end

  @impl true
  def handle_continue(:rebuild, state) do
    unless Application.get_env(:nostr_spam_fighter, :ingest_enabled, true) == false do
      _ = NostrSpamFighter.Policy.Compiler.compile()
    else
      :ets.insert(@meta, {:ready, true})
    end

    {:noreply, state}
  end

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

  @spec lookup(String.t(), String.t()) :: [map()]
  def lookup(rule_type, value)
      when rule_type in ["host", "domain"] and is_binary(value) do
    lookup_host_domain(rule_type, value, 1)
  end

  def lookup(_, _), do: []

  @spec match_url_prefixes(String.t()) :: [map()]
  def match_url_prefixes(url) when is_binary(url) do
    match_url_prefixes(url, 1)
  end

  def match_url_prefixes(_), do: []

  @spec size() :: non_neg_integer()
  def size do
    hd = table_size(host_domain_table())
    url = table_size(url_prefix_table())
    hd + url
  end

  @spec rebuild() :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild do
    result = NostrSpamFighter.Policy.Compiler.compile()
    GenServer.cast(__MODULE__, {:compiled, result})
    result
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    result = NostrSpamFighter.Policy.Compiler.compile()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:install, generation, host_domain, url_prefix}, _from, state) do
    do_install(generation, host_domain, url_prefix)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:compiled, _result}, state), do: {:noreply, state}

  @impl true
  def handle_info({:retire_tables, host_domain, url_prefix}, state) do
    delete_table(host_domain)
    delete_table(url_prefix)
    {:noreply, state}
  end

  @doc false
  @spec install(non_neg_integer(), :ets.tid(), :ets.tid()) :: :ok
  def install(generation, host_domain, url_prefix)
      when is_integer(generation) and generation >= 0 do
    # Compiler may run inside this GenServer (boot rebuild); never call ourselves.
    if self() == Process.whereis(__MODULE__) do
      do_install(generation, host_domain, url_prefix)
    else
      GenServer.call(__MODULE__, {:install, generation, host_domain, url_prefix})
    end
  end

  defp do_install(generation, host_domain, url_prefix) do
    old_hd = host_domain_table()
    old_url = url_prefix_table()

    :ets.insert(@meta, {:host_domain, host_domain})
    :ets.insert(@meta, {:url_prefix, url_prefix})
    :ets.insert(@meta, {:generation, generation})
    :ets.insert(@meta, {:ready, true})

    schedule_retire(old_hd, old_url)
    :ok
  end

  defp schedule_retire(host_domain, url_prefix) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        Process.send_after(pid, {:retire_tables, host_domain, url_prefix}, @retire_ms)

      _ ->
        delete_table(host_domain)
        delete_table(url_prefix)
    end
  end

  @doc false
  @spec new_tables() :: {:ets.tid(), :ets.tid()}
  def new_tables do
    host_domain =
      :ets.new(:nsf_policy_host_domain, [
        :public,
        :bag,
        read_concurrency: true,
        write_concurrency: true
      ])

    url_prefix =
      :ets.new(:nsf_policy_url_prefix, [
        :public,
        :bag,
        read_concurrency: true,
        write_concurrency: true
      ])

    {host_domain, url_prefix}
  end

  @doc false
  def insert_rule(host_domain, url_prefix, rule) do
    meta = rule_meta(rule)

    case rule.rule_type do
      "url_prefix" ->
        :ets.insert(url_prefix, {rule.normalized_value, meta})

      type when type in ["host", "domain"] ->
        :ets.insert(host_domain, {{type, rule.normalized_value}, meta})

      _ ->
        :ok
    end
  end

  defp lookup_host_domain(rule_type, value, retries) do
    case host_domain_table() do
      nil ->
        []

      tid ->
        try do
          tid
          |> :ets.lookup({rule_type, value})
          |> Enum.map(fn {_key, rule} -> rule end)
        rescue
          ArgumentError ->
            if retries > 0, do: lookup_host_domain(rule_type, value, retries - 1), else: []
        end
    end
  end

  defp match_url_prefixes(url, retries) do
    case url_prefix_table() do
      nil ->
        []

      tid ->
        try do
          :ets.foldl(
            fn {prefix, rule}, acc ->
              if String.starts_with?(url, prefix), do: [rule | acc], else: acc
            end,
            [],
            tid
          )
        rescue
          ArgumentError ->
            if retries > 0, do: match_url_prefixes(url, retries - 1), else: []
        end
    end
  end

  defp rule_meta(rule) do
    %{
      entry_id: rule.entry_id,
      rule_type: rule.rule_type,
      normalized_value: rule.normalized_value,
      blocklist_id: rule.blocklist_id,
      blocklist_version_id: rule.blocklist_version_id,
      category_id: rule.category_id,
      category_slug: rule.category_slug,
      blocks_serving: rule.blocks_serving
    }
  end

  defp host_domain_table do
    case :ets.lookup(@meta, :host_domain) do
      [{:host_domain, tid}] -> tid
      _ -> nil
    end
  end

  defp url_prefix_table do
    case :ets.lookup(@meta, :url_prefix) do
      [{:url_prefix, tid}] -> tid
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
