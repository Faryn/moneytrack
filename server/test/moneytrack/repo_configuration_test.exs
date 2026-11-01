defmodule MoneyTrack.RepoConfigurationTest do
  use MoneyTrack.DataCase

  test "runtime database is outside the checkout and uses durable relational storage" do
    database = MoneyTrack.Repo.config()[:database]
    checkout = Path.expand("../../..", __DIR__)
    assert Path.type(database) == :absolute
    refute String.starts_with?(database, checkout <> "/")

    assert %{rows: [["wal"]]} = Repo.query!("PRAGMA journal_mode")
    assert %{rows: [[2]]} = Repo.query!("PRAGMA synchronous")
    assert %{rows: [[1]]} = Repo.query!("PRAGMA foreign_keys")
    # Exqlite configures its own busy handler, which PRAGMA busy_timeout cannot report.
  end
end
