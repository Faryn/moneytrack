# Synthetic identities for scripts/check-connected only. Never seed normal databases.
root = System.fetch_env!("MONEYTRACK_CONNECTED_ROOT") |> Path.expand()

database =
  Application.fetch_env!(:moneytrack, MoneyTrack.Repo)
  |> Keyword.fetch!(:database)
  |> Path.expand()

unless String.starts_with?(database, root <> "/") &&
         System.get_env("MONEYTRACK_CONNECTED_FIXTURES") == "1" do
  raise "Connected fixtures require the isolated check-connected database"
end

for username <- ["native-core-fixture", "ui-connected-fixture"] do
  {:ok, _} =
    MoneyTrack.Accounts.create_user(%{username: username, password: "fixture-passphrase-2026"})
end
