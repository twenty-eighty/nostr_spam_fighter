defmodule NostrSpamFighter.Release do
  @moduledoc """
  Tasks that run inside a production release (migrate, bootstrap admin).
  """

  @app :nostr_spam_fighter

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  def bootstrap_admin do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(NostrSpamFighter.Repo, fn _repo ->
        NostrSpamFighter.Accounts.ensure_bootstrap_admin()
      end)

    case result do
      {:ok, _} ->
        :ok

      {:error, :invalid_pubkey} ->
        raise "INITIAL_ADMIN_PUBKEY is missing or invalid"

      {:error, reason} ->
        raise "Could not bootstrap admin: #{inspect(reason)}"
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
