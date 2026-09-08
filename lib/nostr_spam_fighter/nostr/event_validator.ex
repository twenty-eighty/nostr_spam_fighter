defmodule NostrSpamFighter.Nostr.EventValidator do
  @moduledoc """
  Parses and validates Nostr events before scanning.
  """

  @hex64 ~r/^[0-9a-f]{64}$/
  @hex128 ~r/^[0-9a-f]{128}$/

  @spec validate(map()) :: {:ok, map()} | {:error, atom()}
  def validate(event) when is_map(event) do
    max_content = Application.get_env(:nostr_spam_fighter, :max_content_bytes, 512_000)
    max_tags = Application.get_env(:nostr_spam_fighter, :max_tags, 200)
    max_tag_len = Application.get_env(:nostr_spam_fighter, :max_tag_length, 2_048)
    allowed_kinds = Application.get_env(:nostr_spam_fighter, :ingest_kinds, [30_023])

    cond do
      not valid_hex64?(event["id"]) ->
        {:error, :invalid_id}

      not valid_hex64?(event["pubkey"]) ->
        {:error, :invalid_pubkey}

      not is_integer(event["created_at"]) ->
        {:error, :invalid_created_at}

      event["kind"] not in allowed_kinds ->
        {:error, :unsupported_kind}

      not is_binary(event["content"]) ->
        {:error, :invalid_content}

      byte_size(event["content"]) > max_content ->
        {:error, :content_too_large}

      not is_list(event["tags"]) ->
        {:error, :invalid_tags}

      length(event["tags"]) > max_tags ->
        {:error, :too_many_tags}

      tags_too_long?(event["tags"], max_tag_len) ->
        {:error, :tag_too_long}

      not valid_hex128?(event["sig"]) ->
        {:error, :invalid_signature}

      recompute_id(event) != String.downcase(event["id"]) ->
        {:error, :id_mismatch}

      not verify_signature(event) ->
        {:error, :invalid_signature}

      true ->
        {:ok, normalize(event)}
    end
  end

  def validate(_), do: {:error, :invalid_event}

  @spec recompute_id(map()) :: String.t()
  def recompute_id(event) do
    payload = [
      0,
      event["pubkey"],
      event["created_at"],
      event["kind"],
      event["tags"] || [],
      event["content"] || ""
    ]

    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp verify_signature(event) do
    json = Jason.encode!(event)

    try do
      NostrElixir.Event.verify(json) == true
    rescue
      _ -> false
    end
  end

  defp normalize(event) do
    d_tag = d_tag(event["tags"])
    kind = event["kind"]
    pubkey = String.downcase(event["pubkey"])

    event
    |> Map.put("id", String.downcase(event["id"]))
    |> Map.put("pubkey", pubkey)
    |> Map.put("d_tag", d_tag)
    |> Map.put("article_address", address(kind, pubkey, d_tag))
  end

  def d_tag(tags) do
    Enum.find_value(tags, fn
      ["d", value | _] -> value
      _ -> nil
    end)
  end

  def address(kind, pubkey, d_tag) when is_binary(d_tag), do: "#{kind}:#{pubkey}:#{d_tag}"
  def address(_, _, _), do: nil

  defp tags_too_long?(tags, max) do
    Enum.any?(tags, fn tag ->
      is_list(tag) and Enum.any?(tag, &(is_binary(&1) and byte_size(&1) > max))
    end)
  end

  defp valid_hex64?(value) when is_binary(value), do: Regex.match?(@hex64, String.downcase(value))
  defp valid_hex64?(_), do: false

  defp valid_hex128?(value) when is_binary(value),
    do: Regex.match?(@hex128, String.downcase(value))

  defp valid_hex128?(_), do: false
end
