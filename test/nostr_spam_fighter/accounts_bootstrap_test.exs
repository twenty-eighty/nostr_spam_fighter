defmodule NostrSpamFighter.AccountsBootstrapTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Accounts

  @pubkey String.duplicate("cd", 32)

  setup do
    prev_env = System.get_env("INITIAL_ADMIN_PUBKEY")
    prev_app = Application.get_env(:nostr_spam_fighter, :initial_admin_pubkey)

    on_exit(fn ->
      if prev_env,
        do: System.put_env("INITIAL_ADMIN_PUBKEY", prev_env),
        else: System.delete_env("INITIAL_ADMIN_PUBKEY")

      Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, prev_app)
    end)

    System.put_env("INITIAL_ADMIN_PUBKEY", @pubkey)
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, @pubkey)
    :ok
  end

  test "creates the bootstrap admin once" do
    assert {:ok, :created} = Accounts.ensure_bootstrap_admin()
    assert {:ok, :exists} = Accounts.ensure_bootstrap_admin()
    assert Accounts.get_admin_by_pubkey(@pubkey)
  end

  test "rejects an invalid pubkey" do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)
    assert {:error, :invalid_pubkey} = Accounts.ensure_bootstrap_admin()
  end
end
