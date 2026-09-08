defmodule NostrSpamFighter.Jobs.RescanEventsWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.Event
  alias NostrSpamFighter.Jobs.ScanEventWorker
  alias NostrSpamFighter.Moderation.{Classification, Scan}
  alias NostrSpamFighter.Jobs.WithdrawLabelWorker

  @impl true
  def perform(%Oban.Job{args: args}) do
    mode = Map.get(args, "mode", "existing")
    event_ids = Map.get(args, "event_ids")

    ids =
      cond do
        is_list(event_ids) -> event_ids
        mode == "existing" -> Repo.all(from e in Event, select: e.event_id)
        true -> []
      end

    Enum.each(ids, fn event_id ->
      maybe_withdraw_stale(event_id)

      %{event_id: event_id}
      |> ScanEventWorker.new(queue: :scans)
      |> Oban.insert()
    end)

    Phoenix.PubSub.broadcast(NostrSpamFighter.PubSub, "rescans", {:rescan_enqueued, length(ids)})
    :ok
  end

  defp maybe_withdraw_stale(event_id) do
    latest =
      Repo.one(
        from s in Scan, where: s.event_id == ^event_id, order_by: [desc: s.inserted_at], limit: 1
      )

    if latest do
      Repo.all(from c in Classification, where: c.scan_id == ^latest.id)
      |> Enum.each(fn c ->
        %{event_id: event_id, category_id: c.category_id}
        |> WithdrawLabelWorker.new(queue: :nostr_publish)
        |> Oban.insert()
      end)
    end
  end
end
