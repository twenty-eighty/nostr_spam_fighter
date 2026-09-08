defmodule NostrSpamFighter.Scanner.Kind1Processor do
  @moduledoc """
  Future kind:1 note processor. Not enabled in V1 ingest.

  Adding this module later must not require changes to policy, classification,
  publication, or API foundations — only a new processor and ingest kind.
  """

  @behaviour NostrSpamFighter.Scanner.Processor

  @impl true
  def supported_kind, do: 1

  @impl true
  def extract(event), do: NostrSpamFighter.Scanner.UrlExtractor.extract(event)
end
