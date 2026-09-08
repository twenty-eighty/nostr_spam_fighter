defmodule NostrSpamFighter.Accounts.NostrAuth do
  @moduledoc """
  Verifies NIP-98 kind 27235 login events.
  """

  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.ReplayCache
  alias NostrSpamFighter.Nostr.EventValidator

  @kind 27_235

  def verify(auth_header, conn_info) do
    with {:ok, event_json} <- parse_header(auth_header),
         {:ok, event} <- decode(event_json),
         :ok <- validate_structure(event),
         :ok <- validate_id(event),
         :ok <- validate_timestamps(event),
         :ok <- validate_request(event, conn_info),
         :ok <- reject_replay(event),
         :ok <- verify_sig(event_json),
         {:ok, admin} <- Accounts.enabled_admin?(event["pubkey"]) do
      {:ok, admin}
    end
  end

  defp parse_header("Nostr " <> b64) do
    case Base.decode64(b64) do
      {:ok, json} -> {:ok, json}
      :error -> {:error, :invalid_auth}
    end
  end

  defp parse_header(_), do: {:error, :invalid_auth}

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, event} -> {:ok, event}
      _ -> {:error, :invalid_json}
    end
  end

  defp validate_structure(event) do
    cond do
      event["kind"] != @kind -> {:error, :wrong_kind}
      not is_binary(event["id"]) -> {:error, :invalid_id}
      not is_binary(event["sig"]) -> {:error, :invalid_signature}
      not is_list(event["tags"]) -> {:error, :invalid_tags}
      true -> :ok
    end
  end

  defp validate_id(event) do
    if EventValidator.recompute_id(event) == String.downcase(event["id"] || "") do
      :ok
    else
      {:error, :invalid_id}
    end
  end

  def validate_timestamps(event) do
    now = System.system_time(:second)
    created = event["created_at"]
    window = Application.get_env(:nostr_spam_fighter, :nip98_window_s, 60)
    skew = Application.get_env(:nostr_spam_fighter, :nip98_skew_s, 5)

    cond do
      not is_integer(created) -> {:error, :invalid_created_at}
      created < now - window - skew -> {:error, :stale}
      created > now + skew -> {:error, :future}
      true -> :ok
    end
  end

  defp validate_request(event, conn_info) do
    u = tag(event["tags"], "u")
    method = tag(event["tags"], "method")

    cond do
      method != conn_info.method -> {:error, :method_mismatch}
      not urls_equivalent?(u, conn_info.url) -> {:error, :url_mismatch}
      true -> :ok
    end
  end

  defp reject_replay(event) do
    if ReplayCache.seen?(event["id"]) do
      {:error, :replay}
    else
      ReplayCache.put(event["id"])
      :ok
    end
  end

  defp verify_sig(json) do
    try do
      if NostrElixir.Event.verify(json), do: :ok, else: {:error, :invalid_signature}
    rescue
      _ -> {:error, :invalid_signature}
    end
  end

  defp tag(tags, name) do
    Enum.find_value(tags, fn
      [^name, value | _] -> value
      _ -> nil
    end)
  end

  defp urls_equivalent?(nil, _), do: false

  defp urls_equivalent?(left, right) do
    normalize_url(left) == normalize_url(right)
  end

  defp normalize_url(url) do
    url
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.downcase()
  end
end
