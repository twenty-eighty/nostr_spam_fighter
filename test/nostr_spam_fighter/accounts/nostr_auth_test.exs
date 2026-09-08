defmodule NostrSpamFighter.Accounts.NostrAuthTest do
  use NostrSpamFighter.DataCase, async: false
  alias NostrSpamFighter.Accounts
  alias NostrSpamFighter.Accounts.NostrAuth

  @url "http://localhost:4002/auth/nostr"

  setup do
    keys = NostrElixir.Keys.generate_keypair()
    {:ok, admin} = Accounts.create_admin(%{pubkey: keys.public_key, name: "ops", enabled: true})
    {:ok, keys: keys, admin: admin}
  end

  defp auth_header(keys, opts) do
    kind = Keyword.get(opts, :kind, 27235)
    created = Keyword.get(opts, :created_at, System.system_time(:second))
    url = Keyword.get(opts, :url, @url)
    method = Keyword.get(opts, :method, "POST")
    unsigned = NostrElixir.Event.new(keys.public_key, "", kind, [["u", url], ["method", method]])
    event = unsigned |> Jason.decode!() |> Map.put("created_at", created)
    signed = NostrElixir.Event.sign(Jason.encode!(event), keys.secret_key)
    "Nostr " <> Base.encode64(signed)
  end

  test "valid login", %{keys: keys} do
    header = auth_header(keys, [])
    assert {:ok, admin} = NostrAuth.verify(header, %{method: "POST", url: @url})
    assert admin.pubkey == keys.public_key
  end

  test "wrong kind", %{keys: keys} do
    header = auth_header(keys, kind: 1)
    assert {:error, :wrong_kind} = NostrAuth.verify(header, %{method: "POST", url: @url})
  end

  test "stale and future timestamps" do
    now = System.system_time(:second)
    assert {:error, :stale} = NostrAuth.validate_timestamps(%{"created_at" => now - 10_000})
    assert {:error, :future} = NostrAuth.validate_timestamps(%{"created_at" => now + 10_000})
    assert :ok = NostrAuth.validate_timestamps(%{"created_at" => now})
  end

  test "wrong url and method", %{keys: keys} do
    header = auth_header(keys, url: "http://evil.test/auth")
    assert {:error, :url_mismatch} = NostrAuth.verify(header, %{method: "POST", url: @url})
    header = auth_header(keys, method: "GET")
    assert {:error, :method_mismatch} = NostrAuth.verify(header, %{method: "POST", url: @url})
  end

  test "unknown and disabled admin", %{keys: keys, admin: admin} do
    other = NostrElixir.Keys.generate_keypair()
    header = auth_header(other, [])
    assert {:error, :unknown_admin} = NostrAuth.verify(header, %{method: "POST", url: @url})
    {:ok, _} = Accounts.update_admin(admin, %{enabled: false})
    header = auth_header(keys, [])
    assert {:error, :disabled} = NostrAuth.verify(header, %{method: "POST", url: @url})
  end

  test "replay is rejected", %{keys: keys} do
    header = auth_header(keys, [])
    assert {:ok, _} = NostrAuth.verify(header, %{method: "POST", url: @url})
    assert {:error, :replay} = NostrAuth.verify(header, %{method: "POST", url: @url})
  end
end
