# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :nostr_spam_fighter,
  ecto_repos: [NostrSpamFighter.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  scanner_version: "1.0.0",
  ingest_kinds: [30023],
  ingest_since_s: 86_400,
  ingest_limit: 300,
  ingest_startup_delay_ms: 10_000,
  ingest_concurrency: 2,
  ingest_max_queue: 2_000,
  max_redirects: 8,
  connect_timeout_ms: 5_000,
  request_timeout_ms: 10_000,
  url_timeout_ms: 20_000,
  max_urls_per_event: 50,
  http_concurrency: 4,
  per_host_concurrency: 2,
  # Exact hostnames whose URLs we match without HEAD. These are content-addressed
  # media CDNs; a URL cache would not help because every blob has a new path.
  skip_redirect_hosts: [
    "blossom.primal.net",
    "m.primal.net",
    "image.nostr.build",
    "i.nostr.build"
  ],
  max_content_bytes: 512_000,
  max_tags: 200,
  max_tag_length: 2_048,
  max_url_bytes: 4_096,
  max_redirect_location_bytes: 2_048,
  memory_pressure: true,
  memory_pressure_ratio: 0.75,
  batch_moderation_limit: 500,
  on_demand_idle_ms: 3_000,
  on_demand_timeout_ms: 10_000,
  blocklist_connect_timeout_ms: 15_000,
  blocklist_receive_timeout_ms: 120_000,
  blocklist_max_bytes: 8_000_000,
  blocklist_max_entries: 5_000_000,
  policy_cache_max_entries: 100_000,
  api_rate_limit: [scale_ms: 60_000, limit: 120, burst: 30],
  nip98_window_s: 60,
  nip98_skew_s: 5,
  initial_admin_pubkey: nil,
  require_admin_auth: false,
  moderation_nsec: nil

config :nostr_spam_fighter, Oban,
  repo: NostrSpamFighter.Repo,
  queues: [
    scans: 1,
    network: 2,
    blocklists: 1,
    nostr_publish: 2,
    maintenance: 1
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", NostrSpamFighter.Jobs.ScheduleBlocklistRefreshWorker}
     ]}
  ]

# Configure the endpoint
config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NostrSpamFighterWeb.ErrorHTML, json: NostrSpamFighterWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NostrSpamFighter.PubSub,
  live_view: [signing_salt: "o26W6CUE"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :nostr_spam_fighter, NostrSpamFighter.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  nostr_spam_fighter: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  nostr_spam_fighter: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, truncate: 2_048

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
