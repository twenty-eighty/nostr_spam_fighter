defmodule NostrSpamFighter.Moderation.OnDemand do
  @moduledoc """
  Loads and scans an article when the API asks for it and no result exists yet.
  """

  require Logger

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Relays
  alias NostrSpamFighter.Nostr.{EventFetcher, EventValidator, Ingestor}
  alias NostrSpamFighter.Scanner.Pipeline

  alias NostrSpamFighter.Moderation.{
    ArticleAddress,
    ArticleModerationState
  }

  def ensure(%{kind: kind, pubkey: pubkey, identifier: d_tag} = data) do
    started = System.monotonic_time(:millisecond)
    article = get_article(kind, pubkey, d_tag)

    {fetch_ms, fetch_result} =
      if needs_event?(article) do
        timed(fn -> fetch_and_ingest(data) end)
      else
        {0, :skipped}
      end

    article = get_article(kind, pubkey, d_tag)

    {scan_ms, scan_result} =
      case article do
        %{current_event_id: event_id} = art when is_binary(event_id) ->
          if needs_scan?(art) do
            timed(fn -> Pipeline.run(event_id) end)
          else
            {0, :skipped}
          end

        _ ->
          {0, :skipped}
      end

    total_ms = System.monotonic_time(:millisecond) - started

    Logger.info(
      "article on_demand kind=#{kind} d=#{truncate(d_tag)} pubkey=#{String.slice(pubkey, 0, 8)} " <>
        "fetch=#{format_phase(fetch_ms, fetch_result)} scan=#{format_phase(scan_ms, scan_result)} " <>
        "total_ms=#{total_ms}"
    )

    :ok
  end

  defp needs_event?(nil), do: true
  defp needs_event?(%{current_event_id: nil}), do: true
  defp needs_event?(_), do: false

  defp needs_scan?(article) do
    case Repo.get_by(ArticleModerationState, article_address_id: article.id) do
      %{status: status} when status in ["clean", "matched", "partial", "failed"] -> false
      _ -> true
    end
  end

  defp fetch_and_ingest(%{kind: kind, pubkey: pubkey, identifier: d_tag, relays: hints}) do
    relays = fetch_relays(hints)

    if relays == [] do
      :no_relays
    else
      filter = %{
        "#d" => [d_tag],
        kinds: [kind],
        authors: [pubkey],
        limit: 20
      }

      opts = [
        idle_ms: Application.get_env(:nostr_spam_fighter, :on_demand_idle_ms, 3_000),
        overall_timeout: Application.get_env(:nostr_spam_fighter, :on_demand_timeout_ms, 10_000),
        cache?: false
      ]

      case EventFetcher.fetch(relays, filter, opts) do
        {:ok, events} ->
          case newest_matching(events, kind, pubkey, d_tag) do
            nil ->
              {:ok, :miss, length(events)}

            event ->
              Ingestor.ingest(event, hd(relays), enqueue_scan: false)
              {:ok, :hit, length(events)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - started, result}
  end

  defp format_phase(_ms, :skipped), do: "skipped"
  defp format_phase(ms, :no_relays), do: "no_relays:#{ms}ms"
  defp format_phase(ms, {:ok, :hit, n}), do: "hit:#{ms}ms events=#{n}"
  defp format_phase(ms, {:ok, :miss, n}), do: "miss:#{ms}ms events=#{n}"
  defp format_phase(ms, {:ok, %{status: status}}), do: "#{status}:#{ms}ms"
  defp format_phase(ms, {:error, reason}), do: "error:#{ms}ms reason=#{inspect(reason)}"
  defp format_phase(ms, _), do: "#{ms}ms"

  defp truncate(value) when is_binary(value) and byte_size(value) > 24 do
    String.slice(value, 0, 24) <> "…"
  end

  defp truncate(value), do: value

  defp newest_matching(events, kind, pubkey, d_tag) do
    events
    |> Enum.filter(fn event ->
      event["kind"] == kind and
        String.downcase(event["pubkey"] || "") == String.downcase(pubkey) and
        EventValidator.d_tag(event["tags"] || []) == d_tag
    end)
    |> Enum.max_by(&{&1["created_at"] || 0, &1["id"] || ""}, fn -> nil end)
  end

  defp fetch_relays(hints) do
    ((hints || []) ++ Relays.list_read_urls())
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp get_article(kind, pubkey, d_tag) do
    Repo.get_by(ArticleAddress, kind: kind, pubkey: pubkey, d_tag: d_tag)
  end
end
