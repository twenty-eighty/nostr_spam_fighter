defmodule NostrSpamFighter.Catalog do
  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.Event
  alias NostrSpamFighter.Moderation.{Match, Scan}

  def list_events(limit \\ 100) do
    Repo.all(
      from e in Event, order_by: [desc: e.last_seen_at], limit: ^limit, preload: [:relays, :scans]
    )
  end

  def get_event!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload(
      relays: [],
      scans: [:url_occurrences, :matches, :classifications]
    )
  end

  def list_matches(limit \\ 200) do
    Repo.all(
      from m in Match,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        preload: [:category, :blocklist, :scan]
    )
  end

  def latest_scan(event_id) do
    Repo.one(
      from s in Scan,
        where: s.event_id == ^event_id,
        order_by: [desc: s.inserted_at],
        limit: 1,
        preload: [
          url_occurrences: [resolution: :redirect_hops],
          matches: [:category, :blocklist],
          classifications: [:category]
        ]
    )
  end

  def dashboard_stats do
    %{
      events: Repo.aggregate(Event, :count),
      scans: Repo.aggregate(Scan, :count),
      matched: Repo.aggregate(from(s in Scan, where: s.status == "matched"), :count),
      matches: Repo.aggregate(Match, :count)
    }
  end
end
