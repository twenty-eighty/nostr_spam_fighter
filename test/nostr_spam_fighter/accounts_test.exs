defmodule NostrSpamFighter.AccountsTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Accounts

  @pubkey String.duplicate("ab", 32)

  setup do
    prev_env = System.get_env("INITIAL_ADMIN_PUBKEY")
    prev_app = Application.get_env(:nostr_spam_fighter, :initial_admin_pubkey)
    prev_required = Application.get_env(:nostr_spam_fighter, :require_admin_auth)

    on_exit(fn ->
      if prev_env,
        do: System.put_env("INITIAL_ADMIN_PUBKEY", prev_env),
        else: System.delete_env("INITIAL_ADMIN_PUBKEY")

      Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, prev_app)
      Application.put_env(:nostr_spam_fighter, :require_admin_auth, prev_required)
    end)

    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, false)
    :ok
  end

  test "admin_auth_required? is false without a pubkey in non-prod" do
    refute Accounts.admin_auth_required?()
  end

  test "admin_auth_required? is true when a pubkey is configured" do
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, @pubkey)
    assert Accounts.admin_auth_required?()
  end

  test "admin_auth_required? is true when production requires admin auth" do
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, true)
    assert Accounts.admin_auth_required?()
  end

  test "require_admin_protection! is a no-op when admin auth is optional" do
    assert :ok = Accounts.require_admin_protection!()
  end

  test "require_admin_protection! raises without a valid pubkey when required" do
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, true)

    assert_raise RuntimeError, ~r/INITIAL_ADMIN_PUBKEY/, fn ->
      Accounts.require_admin_protection!()
    end
  end

  test "require_admin_protection! rejects a blank or invalid pubkey" do
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, true)
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, "not-a-pubkey")

    assert_raise RuntimeError, ~r/INITIAL_ADMIN_PUBKEY/, fn ->
      Accounts.require_admin_protection!()
    end
  end

  test "require_admin_protection! accepts a hex pubkey" do
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, true)
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, @pubkey)
    assert :ok = Accounts.require_admin_protection!()
  end

  test "valid_admin_pubkey? accepts 64 hex characters" do
    assert Accounts.valid_admin_pubkey?(@pubkey)
    assert Accounts.valid_admin_pubkey?(String.upcase(@pubkey))
    refute Accounts.valid_admin_pubkey?("")
    refute Accounts.valid_admin_pubkey?("   ")
    refute Accounts.valid_admin_pubkey?(nil)
    refute Accounts.valid_admin_pubkey?("abc")
  end
end
