defmodule NostrSpamFighter.Accounts.ApiKeyTest do
  use NostrSpamFighter.DataCase, async: false
  alias NostrSpamFighter.Accounts

  test "creates hashed key and verifies" do
    {:ok, key} = Accounts.create_api_key(%{name: "pareto"})
    assert String.starts_with?(key.plaintext, "nsf_")
    assert is_binary(key.plaintext)
    stored = Accounts.get_api_key!(key.id)
    refute stored.secret_hash == key.plaintext
    refute String.contains?(stored.secret_hash, String.split(key.plaintext, "_") |> List.last())
    assert {:ok, _} = Accounts.verify_api_key(key.plaintext)
    assert {:error, :invalid} = Accounts.verify_api_key("nsf_nope_secret")
  end

  test "rejects disabled revoked expired and wrong scope" do
    {:ok, key} = Accounts.create_api_key(%{name: "tmp"})
    {:ok, disabled} = Accounts.disable_api_key(key)
    assert {:error, :disabled} = Accounts.verify_api_key(key.plaintext)

    {:ok, key2} = Accounts.create_api_key(%{name: "tmp2"})
    {:ok, _} = Accounts.revoke_api_key(key2)
    assert {:error, :revoked} = Accounts.verify_api_key(key2.plaintext)

    {:ok, key3} =
      Accounts.create_api_key(%{
        name: "tmp3",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    assert {:error, :expired} = Accounts.verify_api_key(key3.plaintext)
    refute Accounts.has_scope?(disabled, "other:scope")
  end

  test "supports multiple independent keys and rotation" do
    {:ok, a} = Accounts.create_api_key(%{name: "prod"})
    {:ok, b} = Accounts.create_api_key(%{name: "staging"})
    assert {:ok, _} = Accounts.verify_api_key(a.plaintext)
    assert {:ok, _} = Accounts.verify_api_key(b.plaintext)
    {:ok, rotated} = Accounts.rotate_api_key(Accounts.get_api_key!(a.id))
    assert {:error, :revoked} = Accounts.verify_api_key(a.plaintext)
    assert {:ok, _} = Accounts.verify_api_key(rotated.plaintext)
  end
end
