defmodule NostrSpamFighter.Scanner.KeyedLock do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def with_lock(key, fun) when is_function(fun, 0) do
    :ok = GenServer.call(__MODULE__, {:acquire, key}, :infinity)

    try do
      fun.()
    after
      GenServer.cast(__MODULE__, {:release, key})
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:acquire, key}, from, state) do
    case Map.get(state, key) do
      nil ->
        {:reply, :ok, Map.put(state, key, {:held, []})}

      {:held, waiters} ->
        {:noreply, Map.put(state, key, {:held, waiters ++ [from]})}
    end
  end

  @impl true
  def handle_cast({:release, key}, state) do
    case Map.get(state, key) do
      {:held, [next | rest]} ->
        GenServer.reply(next, :ok)
        {:noreply, Map.put(state, key, {:held, rest})}

      {:held, []} ->
        {:noreply, Map.delete(state, key)}

      nil ->
        {:noreply, state}
    end
  end
end
