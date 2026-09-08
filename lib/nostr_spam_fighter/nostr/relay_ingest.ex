defmodule NostrSpamFighter.Nostr.RelayIngest do
  @moduledoc """
  Long-lived ingest of configured read relays via nostr_access subscribe.
  """

  use GenServer
  require Logger

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.{IngestQueue, Relay}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def start, do: cast_if_alive(:start)
  def stop, do: cast_if_alive(:stop)
  def reconnect, do: cast_if_alive(:reconnect)

  def running?, do: status().running

  def status do
    case Process.whereis(__MODULE__) do
      nil -> %{running: false, pending: false}
      pid -> GenServer.call(pid, :status)
    end
  end

  @impl true
  def init(opts) do
    delay = startup_delay_ms(opts)
    state = %{subscription: nil, running: true, pending: delay > 0}

    if delay > 0 do
      Logger.info("Relay ingest starts in #{div(delay, 1000)}s")
      Process.send_after(self(), :delayed_subscribe, delay)
      {:ok, state}
    else
      {:ok, state, {:continue, :subscribe}}
    end
  end

  @impl true
  def handle_continue(:subscribe, state), do: {:noreply, subscribe(state)}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{running: state.running, pending: state.pending}, state}
  end

  @impl true
  def handle_cast(:start, state) do
    {:noreply, subscribe(%{state | running: true, pending: false})}
  end

  def handle_cast(:stop, state) do
    cancel(state.subscription)
    Phoenix.PubSub.broadcast(NostrSpamFighter.PubSub, "relays", :ingest_stopped)
    {:noreply, %{state | subscription: nil, running: false, pending: false}}
  end

  def handle_cast(:reconnect, state) do
    cancel(state.subscription)
    {:noreply, subscribe(%{state | subscription: nil, running: true, pending: false})}
  end

  @impl true
  def handle_info({:nostr_event, _pid, event, relay}, %{running: true} = state) do
    IngestQueue.enqueue(event, relay)
    :telemetry.execute([:nostr_spam_fighter, :ingest, :received], %{count: 1}, %{relay: relay})
    {:noreply, state}
  end

  def handle_info({:nostr_event, _pid, _event, _relay}, state), do: {:noreply, state}

  def handle_info({:nostr_eose, _pid, relay}, state) do
    Phoenix.PubSub.broadcast(NostrSpamFighter.PubSub, "relays", {:relay_eose, relay})
    {:noreply, state}
  end

  def handle_info({:nostr_down, _pid, relay, reason}, state) do
    Logger.warning("relay down #{relay}: #{inspect(reason)}")
    Phoenix.PubSub.broadcast(NostrSpamFighter.PubSub, "relays", {:relay_down, relay})
    {:noreply, state}
  end

  def handle_info(:retry, %{running: false} = state), do: {:noreply, state}
  def handle_info(:retry, state), do: {:noreply, subscribe(%{state | pending: false})}

  def handle_info(:delayed_subscribe, %{running: false} = state), do: {:noreply, state}

  def handle_info(:delayed_subscribe, state) do
    {:noreply, subscribe(%{state | pending: false})}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp subscribe(%{running: false} = state), do: %{state | pending: false}

  defp subscribe(state) do
    cancel(state.subscription)
    state = %{state | subscription: nil}
    relays = read_relays()
    filter = ingest_filter()

    if relays == [] do
      Logger.info("No read relays configured")
      state
    else
      case Nostr.Client.subscribe(relays, filter, reconnect_ms: 5_000) do
        {:ok, pid} ->
          Phoenix.PubSub.broadcast(NostrSpamFighter.PubSub, "relays", {:ingest_started, relays})
          %{state | subscription: pid}

        {:error, reason} ->
          Logger.error("Failed to subscribe: #{inspect(reason)}")
          Process.send_after(self(), :retry, 5_000)
          state
      end
    end
  end

  def ingest_filter do
    kinds = Application.get_env(:nostr_spam_fighter, :ingest_kinds, [30_023])
    since_s = Application.get_env(:nostr_spam_fighter, :ingest_since_s, 86_400)
    limit = Application.get_env(:nostr_spam_fighter, :ingest_limit, 300)

    %{kinds: kinds}
    |> maybe_put(:since, since_timestamp(since_s))
    |> maybe_put(:limit, positive_int(limit))
  end

  defp since_timestamp(seconds) when is_integer(seconds) and seconds > 0 do
    System.system_time(:second) - seconds
  end

  defp since_timestamp(_), do: nil

  defp positive_int(value) when is_integer(value) and value > 0, do: value
  defp positive_int(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp read_relays do
    import Ecto.Query

    Repo.all(
      from r in Relay,
        where: r.enabled == true and r.read_enabled == true,
        select: r.url
    )
  rescue
    _ -> []
  end

  defp cancel(nil), do: :ok
  defp cancel(pid), do: Nostr.Client.cancel(pid)

  defp cast_if_alive(message) do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, message), else: :ok
  end

  defp startup_delay_ms(opts) do
    Keyword.get(
      opts,
      :startup_delay_ms,
      Application.get_env(:nostr_spam_fighter, :ingest_startup_delay_ms, 10_000)
    )
  end
end
