defmodule NostrSpamFighter.Nostr.Ingestor do
  @moduledoc """
  Deduplicates events, records relay provenance, and enqueues scans.
  """

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.{Event, EventRelay, EventValidator}
  alias NostrSpamFighter.Jobs.ScanEventWorker
  alias NostrSpamFighter.Moderation.ArticleAddress

  def ingest(event, relay_url, opts \\ []) when is_map(event) do
    case EventValidator.validate(event) do
      {:ok, valid} ->
        persist(valid, relay_url, opts)

      {:error, reason} ->
        :telemetry.execute([:nostr_spam_fighter, :ingest, :rejected], %{count: 1}, %{
          reason: reason
        })

        {:error, reason}
    end
  end

  defp persist(event, relay_url, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      existing = Repo.get(Event, event["id"])

      cond do
        existing ->
          existing
          |> Event.changeset(%{last_seen_at: now})
          |> Repo.update!()

          record_relay(event["id"], relay_url)
          existing

        true ->
          {:ok, inserted} =
            %Event{}
            |> Event.changeset(%{
              event_id: event["id"],
              kind: event["kind"],
              pubkey: event["pubkey"],
              created_at: event["created_at"],
              d_tag: event["d_tag"],
              article_address: event["article_address"],
              raw_event: event,
              first_seen_at: now,
              last_seen_at: now
            })
            |> Repo.insert()

          record_relay(event["id"], relay_url)
          maybe_update_address(inserted)

          if Keyword.get(opts, :enqueue_scan, true) do
            enqueue_scan(inserted.event_id)
          end

          maybe_broadcast_ingested(inserted.event_id)

          inserted
      end
    end)
  end

  defp record_relay(event_id, relay_url) when is_binary(relay_url) do
    %EventRelay{}
    |> EventRelay.changeset(%{event_id: event_id, relay_url: relay_url})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:event_id, :relay_url])
  end

  defp record_relay(_, _), do: :ok

  defp maybe_update_address(%Event{kind: 30_023, d_tag: d_tag} = event) when is_binary(d_tag) do
    address = ArticleAddress.canonical(event.kind, event.pubkey, d_tag)

    case Repo.get_by(ArticleAddress, kind: event.kind, pubkey: event.pubkey, d_tag: d_tag) do
      nil ->
        %ArticleAddress{}
        |> ArticleAddress.changeset(%{
          kind: event.kind,
          pubkey: event.pubkey,
          d_tag: d_tag,
          address: address,
          current_event_id: event.event_id,
          current_event_created_at: event.created_at
        })
        |> Repo.insert()

      current ->
        if newer_revision?(event, current) do
          current
          |> ArticleAddress.changeset(%{
            current_event_id: event.event_id,
            current_event_created_at: event.created_at
          })
          |> Repo.update()
        else
          {:ok, current}
        end
    end
  end

  defp maybe_update_address(_), do: :ok

  defp newer_revision?(event, current) do
    cond do
      is_nil(current.current_event_created_at) -> true
      event.created_at > current.current_event_created_at -> true
      event.created_at < current.current_event_created_at -> false
      event.event_id > (current.current_event_id || "") -> true
      true -> false
    end
  end

  defp maybe_broadcast_ingested(event_id) do
    now = System.monotonic_time(:millisecond)
    last = :persistent_term.get({__MODULE__, :last_broadcast_ms}, 0)

    if now - last >= 400 do
      :persistent_term.put({__MODULE__, :last_broadcast_ms}, now)

      Phoenix.PubSub.broadcast(
        NostrSpamFighter.PubSub,
        "events",
        {:event_ingested, event_id}
      )
    end
  end

  defp enqueue_scan(event_id) do
    %{event_id: event_id}
    |> ScanEventWorker.new(queue: :scans)
    |> Oban.insert()
  end
end
