defmodule MoneyTrack.Release do
  @moduledoc "Administrative commands for a packaged release."
  @app :moneytrack

  def migrate do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_user(username) do
    # Administrative commands must not start another HTTP listener.
    Application.put_env(
      @app,
      MoneyTrackWeb.Endpoint,
      Keyword.put(Application.fetch_env!(@app, MoneyTrackWeb.Endpoint), :server, false)
    )

    {:ok, _} = Application.ensure_all_started(@app)
    password = IO.read(:stdio, :eof)

    case MoneyTrack.Accounts.create_user(%{username: username, password: password}) do
      {:ok, user} ->
        IO.puts("Created account #{user.username}.")

      {:error, changeset} ->
        fields = changeset.errors |> Keyword.keys() |> Enum.uniq() |> Enum.join(", ")
        raise "Account not created. Check #{fields}."
    end
  end
end
