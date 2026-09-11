defmodule NostrSpamFighter.Scanner.Pipeline do
  @moduledoc """
  Event -> processor -> URLs -> redirects -> policy -> evidence -> classifications.
  Historical scans are immutable.
  """

  require Logger

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.Event
  alias NostrSpamFighter.Policy.Cache
  alias NostrSpamFighter.Scanner.{HostLimiter, Kind30023Processor, RedirectResolver}

  alias NostrSpamFighter.Moderation.{
    ArticleAddress,
    ArticleModerationState,
    Classification,
    Match,
    RedirectHop,
    Scan,
    UrlOccurrence,
    UrlResolution
  }

  alias NostrSpamFighter.Jobs.PublishLabelWorker
  alias NostrSpamFighter.Moderation.ArticleState

  @processors %{
    30_023 => Kind30023Processor
  }

  @slow_url_ms 1_000

  @doc """
  Runs a scan for `event_id`.

  Options:

    * `:only_if_needed` - when true, skip if article already has a terminal
      moderation state (`clean` / `matched` / `partial` / `failed`)
  """
  def run(event_id, opts \\ []) do
    NostrSpamFighter.Scanner.KeyedLock.with_lock({:scan, event_id}, fn ->
      if Keyword.get(opts, :only_if_needed, false) and not needs_scan?(event_id) do
        {:ok, :skipped}
      else
        do_run(event_id, opts)
      end
    end)
  end

  defp needs_scan?(event_id) do
    article =
      Repo.get_by(ArticleAddress, current_event_id: event_id) ||
        case Repo.get(Event, event_id) do
          %Event{article_address: address} when is_binary(address) ->
            Repo.get_by(ArticleAddress, address: address)

          _ ->
            nil
        end

    case article do
      nil ->
        true

      article ->
        case Repo.get_by(ArticleModerationState, article_address_id: article.id) do
          %{status: status, event_id: ^event_id}
          when status in ["clean", "matched", "partial", "failed"] ->
            false

          _ ->
            true
        end
    end
  end

  defp do_run(event_id, opts) do
    started = System.monotonic_time(:millisecond)
    event = Repo.get!(Event, event_id)
    processor = Map.fetch!(@processors, event.kind)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    generation = Cache.generation()
    version = Application.get_env(:nostr_spam_fighter, :scanner_version, "1.0.0")

    {:ok, scan} =
      %Scan{}
      |> Scan.changeset(%{
        event_id: event.event_id,
        policy_generation: generation,
        status: "running",
        started_at: now,
        scanner_version: version
      })
      |> Repo.insert()

    try do
      indicators = processor.extract(event.raw_event)
      max_urls = Application.get_env(:nostr_spam_fighter, :max_urls_per_event, 50)
      indicators = Enum.take(indicators, max_urls)

      occurrences = persist_occurrences(scan, indicators)
      resolve_started = System.monotonic_time(:millisecond)
      {resolutions, matches} = resolve_and_match(occurrences, opts)
      resolve_ms = System.monotonic_time(:millisecond) - resolve_started
      classifications = classify(scan, event, matches)
      status = scan_status(resolutions, matches)

      scan =
        scan
        |> Scan.changeset(%{
          status: status,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          urls_discovered: length(occurrences),
          urls_resolved: length(resolutions),
          redirects_followed: Enum.reduce(resolutions, 0, &(&1.redirect_count + &2)),
          matches_found: length(matches)
        })
        |> Repo.update!()

      ArticleState.refresh_for_event(event.event_id)
      maybe_publish(classifications)

      Phoenix.PubSub.broadcast(
        NostrSpamFighter.PubSub,
        "scans",
        {:scan_completed, scan.id, status}
      )

      total_ms = System.monotonic_time(:millisecond) - started
      concurrency = Application.get_env(:nostr_spam_fighter, :http_concurrency, 4)

      Logger.info(
        "scan complete event_id=#{short_id(event.event_id)} status=#{status} " <>
          "urls=#{length(occurrences)} matches=#{length(matches)} " <>
          "resolve_ms=#{resolve_ms} total_ms=#{total_ms} concurrency=#{concurrency}"
      )

      {:ok, scan}
    rescue
      error ->
        total_ms = System.monotonic_time(:millisecond) - started

        Logger.warning(
          "scan failed event_id=#{short_id(event_id)} total_ms=#{total_ms} error=#{Exception.message(error)}"
        )

        scan
        |> Scan.changeset(%{
          status: "failed",
          error: Exception.message(error),
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

        {:error, error}
    end
  end

  defp persist_occurrences(scan, indicators) do
    Enum.map(indicators, fn ind ->
      {:ok, occ} =
        %UrlOccurrence{}
        |> UrlOccurrence.changeset(Map.put(ind, :scan_id, scan.id))
        |> Repo.insert()

      occ
    end)
  end

  defp resolve_and_match(occurrences, opts) do
    grouped =
      occurrences
      |> Enum.group_by(& &1.normalized_url)
      |> Map.to_list()

    concurrency = max(Application.get_env(:nostr_spam_fighter, :http_concurrency, 4), 1)

    grouped
    |> Task.async_stream(
      fn {url, occs} ->
        host = URI.parse(url).host || "_"

        result =
          HostLimiter.with_host(host, fn ->
            RedirectResolver.resolve(url, opts)
          end)

        maybe_log_slow_url(url, result)
        {occs, result}
      end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce({[], []}, fn {:ok, {occs, result}}, {res_acc, match_acc} ->
      primary = hd(occs)
      {resolution, hops} = persist_resolution(primary, result)

      matches =
        Enum.flat_map(occs, fn occ ->
          persist_matches(occ, hops, result.matches)
        end)

      {[resolution | res_acc], matches ++ match_acc}
    end)
  end

  defp maybe_log_slow_url(url, result) do
    duration = result.duration_ms || 0

    if duration >= @slow_url_ms do
      host = URI.parse(url).host || "?"

      Logger.info(
        "url resolve slow host=#{host} duration_ms=#{duration} " <>
          "dns_ms=#{result[:dns_ms] || 0} connect_ms=#{result[:connect_ms] || 0} " <>
          "head_ms=#{result[:head_ms] || 0} status=#{result.status} " <>
          "redirects=#{result.redirect_count}"
      )
    end
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 12)
  defp short_id(_), do: "?"

  defp persist_resolution(occ, result) do
    {:ok, resolution} =
      %UrlResolution{}
      |> UrlResolution.changeset(%{
        url_occurrence_id: occ.id,
        status: result.status,
        final_url: result.final_url,
        final_hostname: result.final_hostname,
        http_status: result.http_status,
        redirect_count: result.redirect_count,
        duration_ms: result.duration_ms,
        error: result.error
      })
      |> Repo.insert()

    hops =
      Enum.map(result.hops, fn hop ->
        {:ok, record} =
          %RedirectHop{}
          |> RedirectHop.changeset(
            Map.put(hop, :url_resolution_id, resolution.id)
            |> Map.drop([:matches, :dns_ms, :connect_ms, :head_ms])
          )
          |> Repo.insert()

        {record, hop.matches}
      end)

    {resolution, hops}
  end

  defp persist_matches(occ, hops, _all_matches) do
    Enum.flat_map(hops, fn {hop, matches} ->
      Enum.map(matches, fn rule ->
        {:ok, match} =
          %Match{}
          |> Match.changeset(%{
            scan_id: occ.scan_id,
            url_occurrence_id: occ.id,
            redirect_hop_id: hop.id,
            category_id: rule.category_id,
            blocklist_id: rule.blocklist_id,
            blocklist_version_id: rule.blocklist_version_id,
            blocklist_entry_id: rule.entry_id,
            matched_url: hop.url,
            matched_hostname: hop.hostname,
            match_type: rule.rule_type
          })
          |> Repo.insert()

        match
      end)
    end)
  end

  defp classify(scan, event, matches) do
    matches
    |> Enum.uniq_by(& &1.category_id)
    |> Enum.map(fn match ->
      {:ok, classification} =
        %Classification{}
        |> Classification.changeset(%{
          scan_id: scan.id,
          event_id: event.event_id,
          category_id: match.category_id,
          status: "current"
        })
        |> Repo.insert()

      classification
    end)
  end

  defp scan_status(resolutions, matches) do
    statuses = Enum.map(resolutions, & &1.status)
    network_fail = Enum.any?(statuses, &(&1 != "completed"))

    cond do
      matches != [] and network_fail -> "partial"
      matches != [] -> "matched"
      network_fail -> "partial"
      true -> "clean"
    end
  end

  defp maybe_publish(classifications) do
    Enum.each(classifications, fn c ->
      %{event_id: c.event_id, category_id: c.category_id}
      |> PublishLabelWorker.new(queue: :nostr_publish)
      |> Oban.insert()
    end)
  end
end
