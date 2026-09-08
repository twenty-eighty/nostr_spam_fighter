defmodule NostrSpamFighter.Nostr.SignerTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Nostr.Signer

  setup do
    prev_env = System.get_env("MODERATION_NSEC")
    prev_app = Application.get_env(:nostr_spam_fighter, :moderation_nsec)

    on_exit(fn ->
      if prev_env,
        do: System.put_env("MODERATION_NSEC", prev_env),
        else: System.delete_env("MODERATION_NSEC")

      Application.put_env(:nostr_spam_fighter, :moderation_nsec, prev_app)
    end)

    System.delete_env("MODERATION_NSEC")
    Application.put_env(:nostr_spam_fighter, :moderation_nsec, nil)
    :ok
  end

  test "reads an nsec from the environment" do
    keys = NostrElixir.Keys.generate_keypair()
    System.put_env("MODERATION_NSEC", keys.nsec)

    assert Signer.secret_key() == keys.secret_key
    assert Signer.public_key() == {:ok, keys.public_key}
  end

  test "reads a hex secret from application config" do
    keys = NostrElixir.Keys.generate_keypair()
    Application.put_env(:nostr_spam_fighter, :moderation_nsec, keys.secret_key)

    assert Signer.secret_key() == keys.secret_key
  end

  test "rejects a blank secret" do
    System.put_env("MODERATION_NSEC", "   ")
    assert Signer.secret_key() == {:error, :missing_moderation_key}
  end

  test "returns an error when no secret is configured" do
    assert Signer.secret_key() == {:error, :missing_moderation_key}
    assert Signer.public_key() == {:error, :missing_moderation_key}
    assert Signer.sign(1985, "", []) == {:error, :missing_moderation_key}
  end
end
