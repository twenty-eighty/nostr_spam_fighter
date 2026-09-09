defmodule NostrSpamFighter.Policy.Cache do
  @moduledoc """
  Bounded ETS read-through cache of policy matches, backed by Postgres.

  Keys are **registrable domains** (eTLD+1). Positive and negative results are
  cached. When the table exceeds `policy_cache_max_entries`, older entries are
  evicted so resident memory stays predictable on small instances.

  Imports and enable/disable only invalidate the cache (and bump policy
  generation); they do not rebuild a full in-memory copy of every blocklist.
  """

  use GenServer

  import Ecto.Query

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.BlocklistEntry

  @meta :nsf_policy_meta
  @default_max_entries 100_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@meta, [:named_table, :set, :public, read_concurrency: true])
    domains = new_domains_table()
    :ets.insert(@meta, {:domains, domains})
    :ets.insert(@meta, {:generation, load_generation()})
    :ets.insert(@meta, {:ready, true})
    {:ok, %{}}
  end

  @impl true
  def handle_call(:invalidate, _from, state) do
    result = do_invalidate()
    {:reply, result, state}
  end

  def handle_call(:clear, _from, state) do
    clear_domains()
    {:reply, :ok, state}
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

  @doc """
  Returns match maps for a registrable domain, using ETS then Postgres.
  """
  @spec lookup_domain(String.t()) :: [map()]
  def lookup_domain(domain) when is_binary(domain) and domain != "" do
    gen = generation()

    case ets_get(domain) do
      {:ok, ^gen, hits} ->
        hits_to_maps(domain, hits)

      {:ok, _other_gen, _hits} ->
        fetch_and_cache(domain, gen)

      :miss ->
        fetch_and_cache(domain, gen)
    end
  end

  def lookup_domain(_), do: []

  @spec size() :: non_neg_integer()
  def size, do: table_size(domains_table())

  @doc """
  Clears the ETS cache and bumps policy generation. Kept as `rebuild/0` for
  call sites that previously recompiled the full policy into memory.
  """
  @spec rebuild() :: {:ok, non_neg_integer()} | {:error, term()}
  def rebuild, do: invalidate()

  @spec invalidate() :: {:ok, non_neg_integer()} | {:error, term()}
  def invalidate do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :invalidate, 30_000)
    else
      do_invalidate()
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

  defp fetch_and_cache(domain, gen) do
    hits = query_domain_hits(domain)
    ets_put(domain, gen, hits)
    maybe_evict()
    hits_to_maps(domain, hits)
  end

  defp query_domain_hits(domain) do
    rows =
      from(e in BlocklistEntry,
        join: v in assoc(e, :blocklist_version),
        join: b in assoc(v, :blocklist),
        join: c in assoc(b, :category),
        where: c.enabled == true,
        where: b.enabled == true,
        where: b.active_version_id == v.id,
        where: e.rule_type in ^["host", "domain"],
        where:
          e.registrable_domain == ^domain or
            (is_nil(e.registrable_domain) and e.normalized_value == ^domain),
        select: {
          c.id,
          b.id,
          v.id,
          e.id
        }
      )
      |> Repo.all()

    rows
    |> Enum.reduce(%{}, fn {category_id, _, _, _} = hit, acc ->
      Map.put_new(acc, category_id, hit)
    end)
    |> Map.values()
  end

  defp hits_to_maps(domain, hits) do
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
  end

  defp ets_get(domain) do
    case domains_table() do
      nil ->
        :miss

      tid ->
        try do
          case :ets.lookup(tid, domain) do
            [{^domain, gen, hits}] -> {:ok, gen, hits}
            _ -> :miss
          end
        rescue
          ArgumentError -> :miss
        end
    end
  end

  defp ets_put(domain, gen, hits) do
    case domains_table() do
      nil ->
        :ok

      tid ->
        try do
          :ets.insert(tid, {domain, gen, hits})
        rescue
          ArgumentError -> :ok
        end
    end
  end

  defp maybe_evict do
    tid = domains_table()
    max = max_entries()
    size = table_size(tid)

    if tid && size > max do
      excess = size - div(max, 2)

      _ =
        :ets.foldl(
          fn {domain, _gen, _hits}, deleted ->
            if deleted < excess do
              :ets.delete(tid, domain)
              deleted + 1
            else
              deleted
            end
          end,
          0,
          tid
        )
    end
  end

  defp do_invalidate do
    clear_domains()
    generation = bump_generation()
    :ets.insert(@meta, {:generation, generation})
    :ets.insert(@meta, {:ready, true})
    {:ok, generation}
  rescue
    error -> {:error, error}
  end

  defp clear_domains do
    case domains_table() do
      nil -> :ok
      tid -> :ets.delete_all_objects(tid)
    end
  rescue
    ArgumentError -> :ok
  end

  defp bump_generation do
    current =
      case Repo.one(from g in "policy_generations", select: max(g.generation)) do
        nil -> 0
        max -> max
      end

    next = current + 1

    Repo.insert_all("policy_generations", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        generation: next,
        reason: "invalidate",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    next
  end

  defp load_generation do
    case Repo.one(from g in "policy_generations", select: max(g.generation)) do
      nil -> 0
      max -> max
    end
  rescue
    _ -> 0
  end

  defp max_entries do
    Application.get_env(:nostr_spam_fighter, :policy_cache_max_entries, @default_max_entries)
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
end
