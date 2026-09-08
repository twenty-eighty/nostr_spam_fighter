defmodule NostrSpamFighter.Application do
  @moduledoc false

  use Application

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
        {Task, &NostrSpamFighter.Policy.restart_blocklist_refreshes/0},
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
end
