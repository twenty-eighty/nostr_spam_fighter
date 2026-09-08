defmodule NostrSpamFighter.Nostr.RelayIngestTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Nostr.RelayIngest

  test "ingest filter limits historical backfill" do
    filter = RelayIngest.ingest_filter()
    assert filter.kinds == [30023]
    assert is_integer(filter.since)
    assert filter.since <= System.system_time(:second)
    assert filter.limit == 300
  end

  test "start and stop toggle ingest" do
    pid = start_supervised!(RelayIngest)
    _ = :sys.get_state(pid)
    assert RelayIngest.running?()

    RelayIngest.stop()
    _ = :sys.get_state(pid)
    refute RelayIngest.running?()

    RelayIngest.start()
    _ = :sys.get_state(pid)
    assert RelayIngest.running?()
  end

  test "startup delay can be cancelled before subscribe" do
    pid = start_supervised!({RelayIngest, startup_delay_ms: 60_000})
    assert RelayIngest.status() == %{running: true, pending: true}

    RelayIngest.stop()
    _ = :sys.get_state(pid)
    assert RelayIngest.status() == %{running: false, pending: false}

    send(pid, :delayed_subscribe)
    _ = :sys.get_state(pid)
    refute RelayIngest.running?()
  end
end
