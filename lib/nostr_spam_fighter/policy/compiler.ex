defmodule NostrSpamFighter.Policy.Compiler do
  @moduledoc false

  alias NostrSpamFighter.Policy.Cache

  @doc """
  Invalidates the read-through cache and bumps policy generation.

  Kept for compatibility with call sites that previously streamed the full
  blocklist set into ETS.
  """
  def compile, do: Cache.invalidate()
end
