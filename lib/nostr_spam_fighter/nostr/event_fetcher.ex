defmodule NostrSpamFighter.Nostr.EventFetcher do
  @moduledoc """
  Fetches events from relays. Overridable in tests via `:event_fetcher`.
  """

  def fetch(relays, filter, opts \\ []) do
    case Application.get_env(:nostr_spam_fighter, :event_fetcher, &Nostr.Client.fetch/3) do
      fun when is_function(fun, 3) -> fun.(relays, filter, opts)
      {mod, fun, args} -> apply(mod, fun, [relays, filter, opts] ++ args)
      _ -> Nostr.Client.fetch(relays, filter, opts)
    end
  end

  def noop(_relays, _filter, _opts), do: {:ok, []}
end
