defmodule MoneyTrack.Sharing.Delivery do
  import Ecto.Query
  import Ecto.Changeset
  import Swoosh.Email, except: [from: 2]
  alias MoneyTrack.{Repo, Mailer}
  alias MoneyTrack.Sharing.{MailJob, SharedExpense}
  alias MoneyTrack.Accounts.User

  def deliver_pending do
    Enum.reduce_while(1..10, :ok, fn _, _ ->
      now = DateTime.utc_now()

      {:ok, job} =
        Repo.transaction(fn ->
          job =
            Repo.one(
              from j in MailJob,
                where: j.status in ["queued", "sending"] and j.available_at <= ^now,
                limit: 1
            )

          if job,
            do:
              job
              |> change(
                status: "sending",
                attempts: job.attempts + 1,
                available_at: DateTime.add(now, 120, :second)
              )
              |> Repo.update!()
        end)

      if job do
        send_job(job)
        {:cont, :ok}
      else
        {:halt, :ok}
      end
    end)
  end

  defp send_job(job) do
    expense = Repo.get!(SharedExpense, job.expense_id)

    if expense.deleted_at || expense.status != "pending" do
      job |> change(status: "cancelled") |> Repo.update!()
    else
      sender = Repo.get!(User, expense.creator_id)

      email =
        new()
        |> to(expense.recipient_email)
        |> Swoosh.Email.from({"MoneyTrack", Application.fetch_env!(:moneytrack, :mail_from)})
        |> subject("MoneyTrack sharing invitation")
        |> header("Message-ID", "<#{job.id}@moneytrack.invalid>")
        |> text_body(
          "#{sender.username} invited you to share an expense on MoneyTrack.\n\nOpen MoneyTrack, sign in, and verify this email address under Account → Email for Sharing. The invitation will appear under Shared.\nAccounts are currently created by the administrator. No payment is made by accepting.\n"
        )

      outcome =
        try do
          Mailer.deliver(email)
        rescue
          _ -> :error
        catch
          :exit, _ -> :error
        end

      attrs =
        case outcome do
          {:ok, _} ->
            [status: "sent"]

          _ when job.attempts >= 5 ->
            [status: "failed"]

          _ ->
            [
              status: "queued",
              available_at: DateTime.add(DateTime.utc_now(), 30 * job.attempts, :second)
            ]
        end

      job |> change(attrs) |> Repo.update!()
    end
  end
end
