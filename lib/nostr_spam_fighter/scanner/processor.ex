defmodule NostrSpamFighter.Scanner.Processor do
  @moduledoc """
  Behaviour for event-kind processors. Processors emit normalized indicators only.
  """

  @callback supported_kind() :: integer()
  @callback extract(map()) :: [map()]
end
