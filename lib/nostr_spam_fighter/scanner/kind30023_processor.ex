defmodule NostrSpamFighter.Scanner.Kind30023Processor do
  @moduledoc """
  Extracts URL indicators from NIP-23 kind 30023 articles.
  """

  @behaviour NostrSpamFighter.Scanner.Processor

  @impl true
  def supported_kind, do: 30_023

  @impl true
  def extract(event), do: NostrSpamFighter.Scanner.UrlExtractor.extract(event)
end
