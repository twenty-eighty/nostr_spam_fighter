defmodule NostrSpamFighter.Accounts do
  @moduledoc """
  Admins and API keys.
  """

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Accounts.{Admin, ApiKey}

  def list_admins, do: Repo.all(from a in Admin, order_by: a.inserted_at)
  def get_admin!(id), do: Repo.get!(Admin, id)
  def get_admin_by_id(id), do: Repo.get(Admin, id)
  def get_admin_by_pubkey(pubkey), do: Repo.get_by(Admin, pubkey: String.downcase(pubkey || ""))

  def create_admin(attrs) do
    %Admin{} |> Admin.changeset(attrs) |> Repo.insert()
  end

  def update_admin(%Admin{} = admin, attrs) do
    admin |> Admin.changeset(attrs) |> Repo.update()
  end

  def change_admin(%Admin{} = admin, attrs \\ %{}), do: Admin.changeset(admin, attrs)

  def touch_login(%Admin{} = admin) do
    admin
    |> Admin.changeset(%{last_login_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def admin_auth_required? do
    Application.get_env(:nostr_spam_fighter, :require_admin_auth, false) or
      present_pubkey?(System.get_env("INITIAL_ADMIN_PUBKEY")) or
      present_pubkey?(Application.get_env(:nostr_spam_fighter, :initial_admin_pubkey))
  end

  def require_admin_protection! do
    if Application.get_env(:nostr_spam_fighter, :require_admin_auth, false) do
      unless valid_admin_pubkey?(configured_admin_pubkey()) do
        raise """
        INITIAL_ADMIN_PUBKEY is missing or invalid.
        Production requires a 64-character hex Nostr pubkey so the admin UI cannot start unprotected.
        """
      end
    end

    :ok
  end

  def valid_admin_pubkey?(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&String.match?(&1, ~r/^[0-9a-f]{64}$/))
  end

  def valid_admin_pubkey?(_), do: false

  def ensure_bootstrap_admin do
    pubkey = configured_admin_pubkey()

    cond do
      not valid_admin_pubkey?(pubkey) ->
        {:error, :invalid_pubkey}

      true ->
        pubkey = pubkey |> String.trim() |> String.downcase()

        case get_admin_by_pubkey(pubkey) do
          %Admin{} ->
            {:ok, :exists}

          nil ->
            with {:ok, _admin} <- create_admin(%{pubkey: pubkey, name: "Bootstrap"}) do
              {:ok, :created}
            end
        end
    end
  end

  defp configured_admin_pubkey do
    System.get_env("INITIAL_ADMIN_PUBKEY") ||
      Application.get_env(:nostr_spam_fighter, :initial_admin_pubkey)
  end

  defp present_pubkey?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_pubkey?(_), do: false

  def enabled_admin?(pubkey) do
    case get_admin_by_pubkey(pubkey) do
      %Admin{enabled: true} = admin -> {:ok, admin}
      %Admin{enabled: false} -> {:error, :disabled}
      nil -> {:error, :unknown_admin}
    end
  end

  def list_api_keys, do: Repo.all(from k in ApiKey, order_by: [desc: k.inserted_at])
  def get_api_key!(id), do: Repo.get!(ApiKey, id)

  def create_api_key(attrs, admin \\ nil) do
    {prefix, secret, plaintext} = generate_secret()
    hash = hash_secret(secret)

    %ApiKey{}
    |> ApiKey.changeset(%{
      name: attrs["name"] || attrs[:name],
      key_prefix: prefix,
      secret_hash: hash,
      scopes: attrs["scopes"] || attrs[:scopes] || ["articles:moderation:read"],
      expires_at: parse_expiry(attrs["expires_at"] || attrs[:expires_at]),
      created_by_admin_id: admin && admin.id
    })
    |> Repo.insert()
    |> case do
      {:ok, key} -> {:ok, %{key | plaintext: plaintext}}
      error -> error
    end
  end

  def update_api_key(%ApiKey{} = key, attrs) do
    key |> ApiKey.changeset(attrs) |> Repo.update()
  end

  def disable_api_key(%ApiKey{} = key), do: update_api_key(key, %{enabled: false})

  def enable_api_key(%ApiKey{revoked_at: nil} = key), do: update_api_key(key, %{enabled: true})
  def enable_api_key(_), do: {:error, :revoked}

  def revoke_api_key(%ApiKey{} = key) do
    update_api_key(key, %{
      enabled: false,
      revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def rotate_api_key(%ApiKey{} = key, admin \\ nil) do
    with {:ok, _} <- revoke_api_key(key) do
      create_api_key(%{name: key.name, scopes: key.scopes, expires_at: key.expires_at}, admin)
    end
  end

  def verify_api_key(nil), do: {:error, :missing}

  def verify_api_key("nsf_" <> rest) do
    case String.split(rest, "_", parts: 2) do
      [prefix, secret] ->
        case Repo.get_by(ApiKey, key_prefix: prefix) do
          nil ->
            {:error, :invalid}

          key ->
            cond do
              key.revoked_at != nil -> {:error, :revoked}
              not key.enabled -> {:error, :disabled}
              expired?(key) -> {:error, :expired}
              not secure_compare(key.secret_hash, hash_secret(secret)) -> {:error, :invalid}
              true -> {:ok, key}
            end
        end

      _ ->
        {:error, :invalid}
    end
  end

  def verify_api_key(_), do: {:error, :invalid}

  def has_scope?(%ApiKey{scopes: scopes}, scope), do: scope in scopes

  def touch_api_key(%ApiKey{} = key, ip) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if is_nil(key.last_used_at) or DateTime.diff(now, key.last_used_at) >= 30 do
      key
      |> ApiKey.changeset(%{last_used_at: now, last_used_ip: ip})
      |> Repo.update()
    else
      {:ok, key}
    end
  end

  def generate_secret do
    prefix = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower) |> String.slice(0, 8)
    secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    {prefix, secret, "nsf_#{prefix}_#{secret}"}
  end

  def hash_secret(secret) do
    :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower)
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp expired?(%ApiKey{expires_at: nil}), do: false

  defp expired?(%ApiKey{expires_at: expires_at}),
    do: DateTime.compare(DateTime.utc_now(), expires_at) == :gt

  defp parse_expiry(nil), do: nil
  defp parse_expiry(""), do: nil
  defp parse_expiry(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp parse_expiry(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
