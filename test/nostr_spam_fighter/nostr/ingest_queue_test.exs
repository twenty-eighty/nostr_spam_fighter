defmodule NostrSpamFighter.Nostr.IngestQueueTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Nostr.IngestQueue

  test "drops events under memory pressure" do
    prev_pressure = Application.get_env(:nostr_spam_fighter, :memory_pressure, :unset)
    prev_fun = Application.get_env(:nostr_spam_fighter, :memory_usage_fun, :unset)
    prev_limit = Application.get_env(:nostr_spam_fighter, :memory_limit_bytes, :unset)

    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 100 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 10)

    on_exit(fn ->
      restore_env(:memory_pressure, prev_pressure)
      restore_env(:memory_usage_fun, prev_fun)
      restore_env(:memory_limit_bytes, prev_limit)
    end)

    IngestQueue.enqueue(%{"id" => "evt"}, "wss://example.com")
    _ = :sys.get_state(IngestQueue)
    assert IngestQueue.status() == %{queued: 0, inflight: 0}
  end

  defp restore_env(key, :unset), do: Application.delete_env(:nostr_spam_fighter, key)
  defp restore_env(key, value), do: Application.put_env(:nostr_spam_fighter, key, value)
end
