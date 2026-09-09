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

  @doc """
  Disables every blocklist and rebuilds the policy cache (empty when all disabled).
  Intended for one-off release ops, e.g. on Render:

      bin/nostr_spam_fighter eval 'NostrSpamFighter.Release.disable_all_blocklists()'
  """
  def disable_all_blocklists do
    load_app()

    {:ok, count, _} =
      Ecto.Migrator.with_repo(NostrSpamFighter.Repo, fn _repo ->
        import Ecto.Query
        alias NostrSpamFighter.Policy
        alias NostrSpamFighter.Policy.Blocklist

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {count, _} =
          from(b in Blocklist, where: b.enabled == true)
          |> NostrSpamFighter.Repo.update_all(set: [enabled: false, updated_at: now])

        wait_for_cache!()
        {:ok, _gen} = Policy.Cache.rebuild()
        IO.inspect({:disabled_blocklists, count, :cache_size, Policy.Cache.size()})
        count
      end)

    count
  end

  defp wait_for_cache!(attempts \\ 50)
  defp wait_for_cache!(0), do: raise("Policy.Cache did not start")

  defp wait_for_cache!(attempts) do
    if Process.whereis(NostrSpamFighter.Policy.Cache) do
      :ok
    else
      Process.sleep(100)
      wait_for_cache!(attempts - 1)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
