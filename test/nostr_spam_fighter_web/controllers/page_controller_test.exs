defmodule NostrSpamFighterWeb.PageControllerTest do
  use NostrSpamFighterWeb.ConnCase, async: false

  setup do
    restore_admin_pubkey()
    :ok
  end

  test "GET / opens the dashboard when no admin pubkey is configured", %{conn: conn} do
    clear_admin_pubkey()
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "GET / redirects to login when an admin pubkey is configured", %{conn: conn} do
    require_admin_pubkey()
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  test "GET / redirects to login when admin auth is required without a pubkey", %{conn: conn} do
    clear_admin_pubkey()
    Application.put_env(:nostr_spam_fighter, :require_admin_auth, true)
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  defp require_admin_pubkey do
    System.put_env("INITIAL_ADMIN_PUBKEY", String.duplicate("aa", 32))
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, String.duplicate("aa", 32))
  end

  defp clear_admin_pubkey do
    System.delete_env("INITIAL_ADMIN_PUBKEY")
    Application.put_env(:nostr_spam_fighter, :initial_admin_pubkey, nil)
  end

  defp restore_admin_pubkey do
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
  end
end
