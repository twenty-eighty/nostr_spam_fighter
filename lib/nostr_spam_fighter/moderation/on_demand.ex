defmodule NostrSpamFighter.Moderation.OnDemand do
  @moduledoc """
  Loads and scans an article when the API asks for it and no result exists yet.
  """

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Relays
  alias NostrSpamFighter.Nostr.{EventFetcher, EventValidator, Ingestor}
  alias NostrSpamFighter.Scanner.Pipeline

  alias NostrSpamFighter.Moderation.{
    ArticleAddress,
    ArticleModerationState
  }

  def ensure(%{kind: kind, pubkey: pubkey, identifier: d_tag} = data) do
    article = get_article(kind, pubkey, d_tag)

    if needs_event?(article) do
      fetch_and_ingest(data)
    end

    article = get_article(kind, pubkey, d_tag)
    scan_if_needed(article)
    :ok
  end

  defp needs_event?(nil), do: true
  defp needs_event?(%{current_event_id: nil}), do: true
  defp needs_event?(_), do: false

  defp scan_if_needed(nil), do: :ok

  defp scan_if_needed(%{current_event_id: event_id} = article) when is_binary(event_id) do
    if needs_scan?(article) do
      Pipeline.run(event_id)
    else
      :ok
    end
  end

  defp scan_if_needed(_), do: :ok

  defp needs_scan?(article) do
    case Repo.get_by(ArticleModerationState, article_address_id: article.id) do
      %{status: status} when status in ["clean", "matched", "partial", "failed"] -> false
      _ -> true
    end
  end

  defp fetch_and_ingest(%{kind: kind, pubkey: pubkey, identifier: d_tag, relays: hints}) do
    relays = fetch_relays(hints)

    if relays == [] do
      :ok
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
              :ok

            event ->
              Ingestor.ingest(event, hd(relays), enqueue_scan: false)
          end

        {:error, _reason} ->
          :ok
      end
    end
  end

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
