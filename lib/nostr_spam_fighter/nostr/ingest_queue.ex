defmodule NostrSpamFighter.Nostr.IngestQueue do
  @moduledoc """
  Bounded ingest worker so relay backfill cannot starve LiveView/DB.
  """

  use GenServer
  require Logger

  alias NostrSpamFighter.Nostr.Ingestor

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def enqueue(event, relay_url), do: GenServer.cast(__MODULE__, {:enqueue, event, relay_url})

  def status do
    case Process.whereis(__MODULE__) do
      nil -> %{queued: 0, inflight: 0}
      pid -> GenServer.call(pid, :status)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{queue: :queue.new(), inflight: 0}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{queued: :queue.len(state.queue), inflight: state.inflight}, state}
  end

  @impl true
  def handle_cast({:enqueue, event, relay_url}, state) do
    max_queue = Application.get_env(:nostr_spam_fighter, :ingest_max_queue, 2_000)

    cond do
      NostrSpamFighter.Memory.tight?() ->
        Logger.warning("ingest dropped, memory pressure")

        :telemetry.execute([:nostr_spam_fighter, :ingest, :dropped], %{count: 1}, %{
          reason: :memory_pressure
        })

        {:noreply, state}

      :queue.len(state.queue) >= max_queue ->
        Logger.warning("ingest queue full, dropping event")

        :telemetry.execute([:nostr_spam_fighter, :ingest, :dropped], %{count: 1}, %{
          reason: :queue_full
        })

        {:noreply, state}

      true ->
        {:noreply, pump(%{state | queue: :queue.in({event, relay_url}, state.queue)})}
    end
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, pump(%{state | inflight: max(state.inflight - 1, 0)})}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, pump(%{state | inflight: max(state.inflight - 1, 0)})}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp pump(state) do
    max = Application.get_env(:nostr_spam_fighter, :ingest_concurrency, 2)

    if state.inflight >= max do
      state
    else
      case :queue.out(state.queue) do
        {:empty, _} ->
          state

        {{:value, {event, relay_url}}, queue} ->
          Task.Supervisor.async_nolink(NostrSpamFighter.IngestTasks, fn ->
            Ingestor.ingest(event, relay_url)
          end)

          pump(%{state | queue: queue, inflight: state.inflight + 1})
      end
    end
  end
end
