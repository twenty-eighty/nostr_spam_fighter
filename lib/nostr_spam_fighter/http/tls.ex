defmodule NostrSpamFighter.HTTP.TLS do
  @moduledoc false

  @doc """
  SSL transport options that trust Mozilla CAs via Castore.

  OTP's OS CA loader is unreliable in slim release images; Castore ships a
  PEM bundle with the app so outbound HTTPS verifies consistently.
  """
  def transport_opts(extra \\ []) when is_list(extra) do
    Keyword.put(extra, :cacertfile, CAStore.file_path())
  end
end
