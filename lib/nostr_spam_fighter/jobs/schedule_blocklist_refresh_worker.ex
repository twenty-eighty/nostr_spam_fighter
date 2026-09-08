defmodule NostrSpamFighter.Jobs.ScheduleBlocklistRefreshWorker do
  use Oban.Worker, queue: :blocklists, max_attempts: 3, unique: [period: 60]

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.Blocklist
  alias NostrSpamFighter.Jobs.RefreshBlocklistWorker

  @impl true
  def perform(_job) do
    {:ok, enqueue_due()}
  end

  def enqueue_due(opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    ids = due_ids(force?)

    Enum.each(ids, fn id ->
      RefreshBlocklistWorker.enqueue(id)
    end)

    length(ids)
  end

  defp due_ids(true) do
    Repo.all(
      from b in Blocklist,
        where: b.enabled == true and b.source_type == "remote",
        where: b.refresh_status not in ^["failed", "rejected"],
        where: is_nil(b.last_error),
        select: b.id
    )
  end

  defp due_ids(false) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.all(
      from b in Blocklist,
        where: b.enabled == true and b.source_type == "remote",
        where: b.refresh_status not in ^["failed", "rejected"],
        where: is_nil(b.last_error),
        where: is_nil(b.next_refresh_at) or b.next_refresh_at <= ^now,
        select: b.id
    )
  end
end
