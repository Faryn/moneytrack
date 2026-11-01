defmodule MoneyTrack.Repo do
  use Ecto.Repo,
    otp_app: :moneytrack,
    adapter: Ecto.Adapters.SQLite3
end
