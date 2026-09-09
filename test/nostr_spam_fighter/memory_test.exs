defmodule NostrSpamFighter.MemoryTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Memory

  setup do
    restore_memory_env()
  end

  test "tight? is false when memory pressure is disabled" do
    Application.put_env(:nostr_spam_fighter, :memory_pressure, false)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 100 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 10)

    refute Memory.tight?()
  end

  test "tight? compares usage against the configured budget" do
    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 100)
    Application.put_env(:nostr_spam_fighter, :memory_pressure_ratio, 0.75)

    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 74 end)
    refute Memory.tight?()

    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 75 end)
    assert Memory.tight?()
  end

  test "snapshot reports usage, limit, and pressure" do
    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 90 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 100)

    assert Memory.snapshot() == %{usage_bytes: 90, limit_bytes: 100, tight?: true}
  end

  defp restore_memory_env do
    keys = [:memory_pressure, :memory_usage_fun, :memory_limit_bytes, :memory_pressure_ratio]

    previous =
      Map.new(keys, fn key ->
        {key, Application.get_env(:nostr_spam_fighter, key, :unset)}
      end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, :unset} -> Application.delete_env(:nostr_spam_fighter, key)
        {key, value} -> Application.put_env(:nostr_spam_fighter, key, value)
      end)
    end)

    :ok
  end
end
