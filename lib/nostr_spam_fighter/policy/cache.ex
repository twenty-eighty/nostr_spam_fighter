defmodule NostrSpamFighter.Policy.Cache do
  @moduledoc """
  ETS-backed compiled policy. PostgreSQL remains authoritative.
  """

  use GenServer

  @table :nsf_policy_cache
  @meta :nsf_policy_meta

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@meta, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(@meta, {:generation, 0})
    :ets.insert(@meta, {:ready, true})
    {:ok, %{}, {:continue, :rebuild}}
  end

  @impl true
  def handle_continue(:rebuild, state) do
    unless Application.get_env(:nostr_spam_fighter, :ingest_enabled, true) == false do
      _ = NostrSpamFighter.Policy.Compiler.compile()
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

  @spec rules() :: [map()]
  def rules do
    case :ets.lookup(@table, :rules) do
      [{:rules, rules}] -> rules
      _ -> []
    end
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
  def handle_cast({:compiled, _result}, state), do: {:noreply, state}

  @spec put_compiled(non_neg_integer(), [map()]) :: :ok
  def put_compiled(generation, rules) do
    :ets.insert(@table, {:rules, rules})
    :ets.insert(@meta, {:generation, generation})
    :ets.insert(@meta, {:ready, true})
    :ok
  end
end
