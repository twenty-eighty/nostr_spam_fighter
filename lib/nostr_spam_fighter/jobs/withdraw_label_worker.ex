defmodule NostrSpamFighter.Jobs.WithdrawLabelWorker do
  use Oban.Worker, queue: :nostr_publish, max_attempts: 5

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => event_id, "category_id" => category_id}}) do
    NostrSpamFighter.Nostr.LabelPublisher.withdraw(event_id, category_id)
  end
end
