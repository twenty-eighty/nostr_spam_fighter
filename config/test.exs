import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :nostr_spam_fighter, NostrSpamFighter.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5433"),
  database:
    System.get_env("POSTGRES_TEST_DB") ||
      "nostr_spam_fighter_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xe/XV+/D/dY6tt2byC8sz5jd9f6R5ll7Bgu+tCcrQYaYoS8K0CmhXOUhSTpSV+ae",
  server: false

# In test we don't send emails
config :nostr_spam_fighter, NostrSpamFighter.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :nostr_spam_fighter, Oban, testing: :manual, queues: false, plugins: false

config :nostr_spam_fighter,
  ingest_enabled: false,
  ingest_startup_delay_ms: 0,
  http_adapter: NostrSpamFighter.Scanner.HTTP.BypassAdapter,
  event_fetcher: {NostrSpamFighter.Nostr.EventFetcher, :noop, []}
