defmodule NostrSpamFighter.Nostr.Signer do
  @moduledoc """
  Loads the moderation secret from `MODERATION_NSEC` and signs events.
  """

  def secret_key do
    case configured_nsec() do
      nsec when is_binary(nsec) -> to_hex(nsec)
      _ -> {:error, :missing_moderation_key}
    end
  end

  def public_key do
    case secret_key() do
      {:error, reason} -> {:error, reason}
      hex -> {:ok, keys_public(hex)}
    end
  end

  def sign(kind, content, tags) do
    case {secret_key(), public_key()} do
      {{:error, reason}, _} ->
        {:error, reason}

      {secret, {:ok, pubkey}} ->
        unsigned = NostrElixir.Event.new(pubkey, content, kind, tags)
        signed = NostrElixir.Event.sign(unsigned, secret)
        {:ok, Jason.decode!(signed)}
    end
  end

  defp configured_nsec do
    [
      System.get_env("MODERATION_NSEC"),
      Application.get_env(:nostr_spam_fighter, :moderation_nsec)
    ]
    |> Enum.find(&present_nsec?/1)
    |> case do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end

  defp present_nsec?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_nsec?(_), do: false

  defp to_hex("nsec" <> _ = nsec), do: NostrElixir.Keys.secret_key_to_hex(nsec)
  defp to_hex(hex), do: String.downcase(String.trim(hex))

  defp keys_public(secret) do
    keys = NostrElixir.Keys.parse_keys(secret)
    NostrElixir.Keys.get_public_key(keys)
  end
end
