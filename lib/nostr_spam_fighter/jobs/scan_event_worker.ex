defmodule NostrSpamFighter.Jobs.ScanEventWorker do
  use Oban.Worker,
    queue: :scans,
    max_attempts: 5,
    unique: [period: 60, keys: [:event_id]]

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    case NostrSpamFighter.Scanner.Pipeline.run(event_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
