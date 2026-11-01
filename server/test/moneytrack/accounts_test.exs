defmodule MoneyTrack.AccountsTest do
  use MoneyTrack.DataCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.{Accounts, Repo}
  alias MoneyTrack.Accounts.Session

  test "username/password authentication normalizes usernames and never stores the password" do
    {:ok, account} = Accounts.create_user(%{username: "  Example.User  ", password: password()})
    assert account.username == "example.user"
    assert account.password == nil
    refute account.hashed_password == password()
    assert {:ok, ^account} = Accounts.authenticate("EXAMPLE.USER", password())
    assert :error = Accounts.authenticate("example.user", "incorrect")
    assert :error = Accounts.authenticate("missing-account", password())
    assert {:error, _} = Accounts.create_user(%{username: "Example.User", password: password()})
    assert {:error, _} = Accounts.create_user(%{username: "bad name", password: password()})

    assert {:error, _} =
             Accounts.create_user(%{username: "too_long", password: String.duplicate("x", 73)})
  end

  test "tokens are hashed, type scoped, expiring, and revocable" do
    user = user()
    {:ok, token, session} = Accounts.create_session(user, "device", "Test phone")
    refute Repo.get!(Session, session.id).token_hash == token
    assert {:ok, ^user, ^session} = Accounts.fetch_session(token, "device")
    assert :error = Accounts.fetch_session(token, "browser")
    assert :error = Accounts.fetch_session("not a token", "device")

    session
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert :error = Accounts.fetch_session(token, "device")
    {:ok, second, session} = Accounts.create_session(user, "device", "Other phone")
    assert :ok = Accounts.revoke_session(session)
    assert :error = Accounts.fetch_session(second, "device")
  end
end
