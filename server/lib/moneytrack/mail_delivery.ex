defmodule MoneyTrack.MailDelivery do
  @moduledoc "Small durable mail queue. Delivery is at least once; repeated mail carries the same code and message ID."
  use GenServer
  import Ecto.Query
  import Swoosh.Email, except: [from: 2]
  alias MoneyTrack.{Repo, Mailer}
  alias MoneyTrack.MailDelivery.Job
  alias MoneyTrack.Accounts.EmailChallenge

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_) do
    if Application.get_env(:moneytrack, :mail_delivery_polling, false),
      do: Process.send_after(self(), :deliver, 3_000)

    {:ok, nil}
  end

  @impl true
  def handle_info(:deliver, state) do
    deliver_pending()
    Process.send_after(self(), :deliver, 3_000)
    {:noreply, state}
  end

  def deliver_pending do
    if Application.get_env(:moneytrack, :email_delivery_enabled, false) do
      # One worker, bounded batch. A lease recovers a process crash between delivery and acknowledgement.
      Enum.reduce_while(1..10, :ok, fn _, _ ->
        case claim() do
          nil ->
            {:halt, :ok}

          job ->
            deliver(job)
            {:cont, :ok}
        end
      end)

      MoneyTrack.Sharing.Delivery.deliver_pending()
    end
  end

  defp claim do
    now = DateTime.utc_now()

    {:ok, job} =
      Repo.transaction(fn ->
        job =
          Repo.one(
            from j in Job,
              where: j.status in ["queued", "sending"] and j.available_at <= ^now,
              order_by: [asc: j.inserted_at],
              limit: 1
          )

        if job,
          do:
            job
            |> Ecto.Changeset.change(
              status: "sending",
              attempts: job.attempts + 1,
              available_at: DateTime.add(now, 120, :second)
            )
            |> Repo.update!()
      end)

    job
  end

  defp deliver(job) do
    challenge = Repo.get!(EmailChallenge, job.challenge_id)

    if challenge.retired_at || DateTime.compare(challenge.expires_at, DateTime.utc_now()) != :gt do
      finish(job, "cancelled")
    else
      case Phoenix.Token.decrypt(MoneyTrackWeb.Endpoint, "mail-payload-v1", job.encrypted_payload,
             max_age: 1_800
           ) do
        {:ok, %{address: address, code: code}} ->
          email =
            new()
            |> to(address)
            |> Swoosh.Email.from({"Spendie", Application.fetch_env!(:moneytrack, :mail_from)})
            |> subject("Your Spendie verification code / Dein Spendie-Bestätigungscode")
            |> header("Message-ID", "<#{job.id}@moneytrack.invalid>")
            |> text_body(
              "Your Spendie verification code is #{code}.\n\nIt expires after 30 minutes. Use only the most recently requested code.\nIf you didn't request this, you can ignore this message.\n\n--- Deutsch ---\n\nDein Spendie-Bestätigungscode lautet #{code}.\n\nEr ist 30 Minuten gültig. Verwende nur den zuletzt angeforderten Code.\nWenn du keinen Code angefordert hast, kannst du diese Nachricht ignorieren."
            )

          # Adapter error values may contain the full message. Never log or persist them.
          case safe_deliver(email) do
            :ok ->
              finish(job, "sent")

            :error ->
              if job.attempts >= 5 do
                finish(job, "failed")
              else
                job
                |> Ecto.Changeset.change(
                  status: "queued",
                  available_at:
                    DateTime.add(DateTime.utc_now(), min(30 * job.attempts, 120), :second)
                )
                |> Repo.update!()
              end
          end

        _ ->
          finish(job, "failed")
      end
    end
  end

  defp safe_deliver(email) do
    case Mailer.deliver(email) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp finish(job, status),
    do: job |> Ecto.Changeset.change(status: status, encrypted_payload: nil) |> Repo.update!()
end
