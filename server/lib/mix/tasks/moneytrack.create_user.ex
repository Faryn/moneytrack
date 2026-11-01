defmodule Mix.Tasks.Moneytrack.CreateUser do
  use Mix.Task
  @shortdoc "Create an account (password supplied through stdin)"
  def run([username]) do
    Mix.Task.run("app.start")
    password = IO.read(:stdio, :eof)

    if not is_binary(password),
      do: Mix.raise("Supply a password through stdin using scripts/create-user.")

    case MoneyTrack.Accounts.create_user(%{username: username, password: password}) do
      {:ok, user} ->
        Mix.shell().info("Created account #{user.username}.")

      {:error, changeset} ->
        fields = changeset.errors |> Keyword.keys() |> Enum.uniq() |> Enum.join(", ")

        Mix.raise(
          "Account not created. Check #{fields}. Username: 3–32 letters/numbers/._-. Password: 12–72 bytes."
        )
    end
  end

  def run(_), do: Mix.raise("Usage: mix moneytrack.create_user USERNAME (password on stdin)")
end
