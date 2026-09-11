import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/nostr_spam_fighter start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint, server: true
end

config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/nostr_spam_fighter_web/router\.ex$"E,
        ~r"lib/nostr_spam_fighter_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

config :nostr_spam_fighter,
  initial_admin_pubkey: System.get_env("INITIAL_ADMIN_PUBKEY"),
  moderation_nsec: System.get_env("MODERATION_NSEC"),
  max_redirects: String.to_integer(System.get_env("MAX_REDIRECTS") || "8"),
  connect_timeout_ms: String.to_integer(System.get_env("CONNECT_TIMEOUT_MS") || "5000"),
  request_timeout_ms: String.to_integer(System.get_env("REQUEST_TIMEOUT_MS") || "10000"),
  url_timeout_ms: String.to_integer(System.get_env("URL_TIMEOUT_MS") || "20000"),
  max_urls_per_event: String.to_integer(System.get_env("MAX_URLS_PER_EVENT") || "50"),
  max_url_bytes: String.to_integer(System.get_env("MAX_URL_BYTES") || "4096"),
  http_concurrency: String.to_integer(System.get_env("HTTP_CONCURRENCY") || "4"),
  per_host_concurrency: String.to_integer(System.get_env("PER_HOST_CONCURRENCY") || "2"),
  batch_moderation_limit: String.to_integer(System.get_env("BATCH_MODERATION_LIMIT") || "500"),
  ingest_since_s: String.to_integer(System.get_env("INGEST_SINCE_S") || "86400"),
  ingest_limit: String.to_integer(System.get_env("INGEST_LIMIT") || "300"),
  ingest_concurrency: String.to_integer(System.get_env("INGEST_CONCURRENCY") || "2"),
  on_demand_idle_ms: String.to_integer(System.get_env("ON_DEMAND_IDLE_MS") || "3000"),
  on_demand_timeout_ms: String.to_integer(System.get_env("ON_DEMAND_TIMEOUT_MS") || "10000"),
  blocklist_connect_timeout_ms:
    String.to_integer(System.get_env("BLOCKLIST_CONNECT_TIMEOUT_MS") || "15000"),
  blocklist_receive_timeout_ms:
    String.to_integer(System.get_env("BLOCKLIST_RECEIVE_TIMEOUT_MS") || "120000"),
  blocklist_max_bytes: String.to_integer(System.get_env("BLOCKLIST_MAX_BYTES") || "8000000")

if skip_hosts = System.get_env("SKIP_REDIRECT_HOSTS") do
  config :nostr_spam_fighter,
    skip_redirect_hosts:
      skip_hosts
      |> String.split(",", trim: true)
      |> Enum.map(&String.downcase(String.trim(&1)))
      |> Enum.reject(&(&1 == ""))
end

if memory_limit = System.get_env("MEMORY_LIMIT_BYTES") do
  config :nostr_spam_fighter, memory_limit_bytes: String.to_integer(memory_limit)
end

if config_env() == :prod do
  unless NostrSpamFighter.Accounts.valid_admin_pubkey?(System.get_env("INITIAL_ADMIN_PUBKEY")) do
    raise """
    environment variable INITIAL_ADMIN_PUBKEY is missing or invalid.
    Production requires a 64-character hex Nostr pubkey so the admin UI cannot start unprotected.
    """
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  repo_opts = [
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
  ]

  repo_opts =
    if System.get_env("ECTO_SSL") in ~w(true 1) do
      Keyword.merge(repo_opts, ssl: true, ssl_opts: [verify: :verify_none])
    else
      repo_opts
    end

  config :nostr_spam_fighter, NostrSpamFighter.Repo, repo_opts

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      System.get_env("RENDER_EXTERNAL_HOSTNAME") ||
      "example.com"

  config :nostr_spam_fighter, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :nostr_spam_fighter, NostrSpamFighterWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :nostr_spam_fighter, NostrSpamFighter.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
