import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :moneytrack, MoneyTrack.Repo, pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :moneytrack, MoneyTrackWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xpmMohF8gSaNaZUXE0YdoxDNE84kSBbYxQ1cTrH7wNS3LMrY38BOJ+OcyJz3RBg8",
  server: false

# In test we don't send emails
config :moneytrack, MoneyTrack.Mailer, adapter: Swoosh.Adapters.Test

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

# Keep production password hashing at its normal cost.
config :bcrypt_elixir, log_rounds: 4

config :moneytrack,
  email_delivery_enabled: true,
  mail_delivery_polling: false,
  mail_from: "noreply@moneytrack.invalid"
