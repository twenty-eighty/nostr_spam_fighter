defmodule NostrSpamFighter.Accounts.RateLimiter do
  @moduledoc "API-key rate limiter backed by Hammer ETS."

  use Hammer, backend: :ets

  def check(key_id, cost \\ 1) do
    cfg = Application.get_env(:nostr_spam_fighter, :api_rate_limit, scale_ms: 60_000, limit: 120)
    scale = Keyword.get(cfg, :scale_ms, 60_000)
    limit = Keyword.get(cfg, :limit, 120)

    case hit("api:#{key_id}", scale, limit, cost) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end
end
