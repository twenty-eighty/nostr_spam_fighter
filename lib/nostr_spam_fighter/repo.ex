defmodule NostrSpamFighter.Repo do
  use Ecto.Repo,
    otp_app: :nostr_spam_fighter,
    adapter: Ecto.Adapters.Postgres
end
