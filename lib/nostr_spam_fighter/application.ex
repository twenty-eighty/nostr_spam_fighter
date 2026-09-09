defmodule NostrSpamFighter.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    NostrSpamFighter.Accounts.require_admin_protection!()
    attach_blocklist_refresh_telemetry()

    children =
      [
        NostrSpamFighterWeb.Telemetry,
        NostrSpamFighter.Repo,
        {DNSCluster,
         query: Application.get_env(:nostr_spam_fighter, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: NostrSpamFighter.PubSub},
        {Oban, Application.fetch_env!(:nostr_spam_fighter, Oban)},
        Supervisor.child_spec({Task, &NostrSpamFighter.Policy.restart_blocklist_refreshes/0},
          id: :restart_blocklist_refreshes
        ),
        Supervisor.child_spec({Task, &schedule_registrable_domain_backfill/0},
          id: :registrable_domain_backfill
        ),
        NostrSpamFighter.Accounts.RateLimiter,
        NostrSpamFighter.Policy.Cache,
        NostrSpamFighter.Accounts.ReplayCache,
        {Task.Supervisor, name: NostrSpamFighter.IngestTasks},
        NostrSpamFighter.Nostr.IngestQueue,
        NostrSpamFighterWeb.Endpoint
      ] ++ ingest_children()

    opts = [strategy: :one_for_one, name: NostrSpamFighter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NostrSpamFighterWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp attach_blocklist_refresh_telemetry do
    handler = "nsf-blocklist-refresh-exception"
    :telemetry.detach(handler)

    :telemetry.attach(
      handler,
      [:oban, :job, :exception],
      &NostrSpamFighter.Jobs.RefreshBlocklistWorker.handle_telemetry/4,
      nil
    )
  end

  defp ingest_children do
    if Application.get_env(:nostr_spam_fighter, :ingest_enabled, true) do
      [NostrSpamFighter.Nostr.RelayIngest]
    else
      []
    end
  end

  defp schedule_registrable_domain_backfill do
    if Application.get_env(:nostr_spam_fighter, :registrable_domain_backfill, true) do
      # Wait for port bind / health checks before competing for the DB pool.
      Process.sleep(30_000)

      if NostrSpamFighter.Policy.RegistrableDomainBackfill.pending?() do
        _ = NostrSpamFighter.Policy.RegistrableDomainBackfill.run()
      else
        Logger.info("registrable_domain backfill: nothing to do")
      end
    end

    :ok
  end
end
