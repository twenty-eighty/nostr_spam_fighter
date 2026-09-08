defmodule NostrSpamFighter.Policy.Namespace do
  @moduledoc """
  Public NIP-32 classification namespace. This value is a protocol constant.
  """

  @content "space.pareto.content"

  @spec content() :: String.t()
  def content, do: @content
end
