defmodule NostrSpamFighter.Accounts.ReplayCache do
  @moduledoc false
  use GenServer

  @table :nsf_nip98_replay

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  def seen?(id), do: match?([{^id, _}], :ets.lookup(@table, id))

  def put(id) do
    expires = System.system_time(:second) + 120
    :ets.insert(@table, {id, expires})
    :ok
  end
end
