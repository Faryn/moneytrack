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

for username <- [
      "native-core-fixture",
      "ui-connected-fixture",
      "shared-a-fixture",
      "shared-b-fixture",
      "shared-outsider-fixture"
    ] do
  {:ok, _} =
    MoneyTrack.Accounts.create_user(%{username: username, password: "fixture-passphrase-2026"})
end

for username <- ["shared-b-fixture"] do
  user = MoneyTrack.Repo.get_by!(MoneyTrack.Accounts.User, username: username)

  MoneyTrack.Repo.insert!(%MoneyTrack.Accounts.VerifiedEmail{
    user_id: user.id,
    address: "shared-b@example.org",
    verified_at: DateTime.utc_now()
  })
end

# The UI fixture starts with an accepted relationship but an empty personal ledger,
# so the explicit-copy screen and subsequent connection-reuse flow can both be exercised.
ui = MoneyTrack.Repo.get_by!(MoneyTrack.Accounts.User, username: "ui-connected-fixture")
peer = MoneyTrack.Repo.get_by!(MoneyTrack.Accounts.User, username: "shared-b-fixture")
[low, high] = Enum.sort([ui.id, peer.id])
MoneyTrack.Repo.insert!(%MoneyTrack.Sharing.Connection{user_low: low, user_high: high})
