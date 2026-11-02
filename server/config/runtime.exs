import Config

# Live databases must stay outside the source checkout, which may be cloud-synced.
data_directory =
  System.get_env("MONEYTRACK_DATA_DIR") ||
    case :os.type() do
      {:unix, :darwin} ->
        Path.join(System.user_home!(), "Library/Application Support/MoneyTrack")

      _ ->
        Path.join(
          System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share"),
          "moneytrack"
        )
    end

database_override =
  if config_env() == :test,
    do: System.get_env("MONEYTRACK_TEST_DATABASE_PATH"),
    else: System.get_env("DATABASE_PATH")

database_path =
  database_override ||
    if config_env() == :prod do
      raise "DATABASE_PATH must be an absolute path on persistent host-local storage"
    else
      partition = if config_env() == :test, do: System.get_env("MIX_TEST_PARTITION", ""), else: ""

      Path.join([data_directory, Atom.to_string(config_env()), "moneytrack#{partition}.sqlite3"])
    end

unless Path.type(database_path) == :absolute do
  raise "The SQLite database path must be absolute"
end

database_path = Path.expand(database_path)
checkout = Path.expand("../..", __DIR__)

if database_path == checkout or String.starts_with?(database_path, checkout <> "/") do
  raise "SQLite must be outside the repository; set MONEYTRACK_DATA_DIR to a host-local directory"
end

File.mkdir_p!(Path.dirname(database_path))
config :moneytrack, MoneyTrack.Repo, database: database_path

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
#     PHX_SERVER=true bin/moneytrack start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :moneytrack, MoneyTrackWeb.Endpoint, server: true
end

config :moneytrack, MoneyTrackWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :moneytrack, MoneyTrackWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/moneytrack_web/router\.ex$"E,
        ~r"lib/moneytrack_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
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

  host = System.fetch_env!("PHX_HOST")
  bind_address = System.get_env("PHX_BIND_IP", "127.0.0.1")

  ip =
    case :inet.parse_address(String.to_charlist(bind_address)) do
      {:ok, address} -> address
      _ -> raise "PHX_BIND_IP must be a numeric IPv4 or IPv6 address"
    end

  config :moneytrack, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :moneytrack, MoneyTrackWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Production defaults to loopback; deployments explicitly select a private IP.
      ip: ip
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :moneytrack, MoneyTrackWeb.Endpoint,
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
  #     config :moneytrack, MoneyTrackWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :moneytrack, MoneyTrack.Mailer,
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
