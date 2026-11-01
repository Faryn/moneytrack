defmodule MoneyTrack.Accounts.EmailVerification do
  @moduledoc "Mailbox ownership proof only; does not enable email login or account recovery."
  import Ecto.Query
  alias MoneyTrack.Repo
  alias MoneyTrack.Accounts.{EmailChallenge, VerifiedEmail}
  alias MoneyTrack.MailDelivery.Job
  @lifetime 30 * 60

  def status(user) do
    now = DateTime.utc_now()
    verified = Repo.get_by(VerifiedEmail, user_id: user.id)

    pending =
      Repo.one(
        from c in EmailChallenge,
          where:
            c.user_id == ^user.id and is_nil(c.retired_at) and c.expires_at > ^now and
              c.attempts < 5,
          order_by: [desc: c.inserted_at],
          limit: 1
      )

    job = pending && Repo.get_by(Job, challenge_id: pending.id)

    %{
      deliveryStatus: job && job.status,
      verifiedEmail: verified && verified.address,
      pendingEmail: pending && pending.address,
      verificationID: pending && pending.id,
      expiresAt: pending && DateTime.to_iso8601(pending.expires_at)
    }
  end

  def request(user, email, request_id) do
    with true <- Application.get_env(:moneytrack, :email_delivery_enabled, false),
         {:ok, address} <- normalize(email),
         {:ok, id} <- Ecto.UUID.cast(request_id) do
      transaction(fn ->
        existing = Repo.get(EmailChallenge, id)

        cond do
          existing && existing.user_id == user.id && existing.address == address -> :ok
          existing -> Repo.rollback(:invalid_request)
          Repo.get_by(VerifiedEmail, user_id: user.id) -> Repo.rollback(:already_verified)
          true -> create(user, address, id)
        end

        status(user)
      end)
    else
      false -> {:error, :delivery_unavailable}
      _ -> {:error, :invalid_email}
    end
  end

  def verify(user, id, code) do
    with {:allow, _} <- MoneyTrack.RateLimit.hit("email-verify:#{user.id}", 60_000, 20),
         {:ok, id} <- Ecto.UUID.cast(id),
         true <- is_binary(code) and byte_size(code) == 8 do
      transaction(fn ->
        now = DateTime.utc_now()
        challenge = Repo.get_by(EmailChallenge, id: id, user_id: user.id)

        if is_nil(challenge) || challenge.retired_at || challenge.attempts >= 5 ||
             DateTime.compare(challenge.expires_at, now) != :gt do
          Repo.rollback(:invalid_code)
        end

        # Failed attempts must commit; returning an error value deliberately does not roll back.
        challenge |> Ecto.Changeset.change(attempts: challenge.attempts + 1) |> Repo.update!()

        if Bcrypt.verify_pass(code, challenge.code_hash) do
          case %VerifiedEmail{}
               |> VerifiedEmail.changeset(%{
                 user_id: user.id,
                 address: challenge.address,
                 verified_at: now
               })
               |> Repo.insert() do
            {:ok, _} ->
              challenge |> Ecto.Changeset.change(retired_at: now) |> Repo.update!()
              cancel_pending_mail(challenge.id)
              {:ok, status(user)}

            {:error, _} ->
              {:error, :address_unavailable}
          end
        else
          {:error, :invalid_code}
        end
      end)
      |> case do
        {:ok, result} -> result
        error -> error
      end
    else
      {:deny, _} -> {:error, :rate_limited}
      _ -> {:error, :invalid_code}
    end
  end

  def message(reason) do
    case reason do
      :rate_limited -> "Too many requests. Please try again later."
      :delivery_unavailable -> "Email delivery hasn't been configured for this server."
      :invalid_email -> "Enter a valid email address."
      :already_verified -> "This account already has a verified email address."
      :address_unavailable -> "This email address couldn't be verified for this account."
      :invalid_request -> "Start a new verification request."
      _ -> "The code is incorrect or expired. Request a new code after five attempts."
    end
  end

  def normalize(email) when is_binary(email) do
    value = email |> String.trim() |> String.downcase()
    # ASCII mailbox syntax only, without display names, controls, or quoted local parts.
    valid =
      with [local, domain] <- String.split(value, "@"),
           true <- byte_size(local) in 1..64,
           true <- Regex.match?(~r/\A[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+\z/, local),
           false <-
             String.starts_with?(local, ".") || String.ends_with?(local, ".") ||
               String.contains?(local, ".."),
           labels when length(labels) >= 2 <- String.split(domain, ".") do
        Enum.all?(labels, fn label ->
          byte_size(label) in 1..63 &&
            Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/, label)
        end)
      else
        _ -> false
      end

    if byte_size(value) <= 254 && valid, do: {:ok, value}, else: {:error, :invalid_email}
  end

  def normalize(_), do: {:error, :invalid_email}

  defp create(user, address, id) do
    now = DateTime.utc_now()
    since = DateTime.add(now, -1, :hour)

    if Repo.aggregate(
         from(c in EmailChallenge, where: c.user_id == ^user.id and c.inserted_at > ^since),
         :count
       ) >= 3,
       do: Repo.rollback(:rate_limited)

    old_ids =
      Repo.all(
        from c in EmailChallenge,
          where: c.user_id == ^user.id and is_nil(c.retired_at),
          select: c.id
      )

    Repo.update_all(from(c in EmailChallenge, where: c.id in ^old_ids), set: [retired_at: now])
    Enum.each(old_ids, &cancel_pending_mail/1)

    code =
      :crypto.strong_rand_bytes(8)
      |> :binary.decode_unsigned()
      |> rem(100_000_000)
      |> Integer.to_string()
      |> String.pad_leading(8, "0")

    challenge =
      Repo.insert!(%EmailChallenge{
        id: id,
        user_id: user.id,
        address: address,
        code_hash: Bcrypt.hash_pwd_salt(code),
        expires_at: DateTime.add(now, @lifetime, :second)
      })

    # A restart must not lose delivery. Raw codes are encrypted at rest in the durable mail queue.
    payload =
      Phoenix.Token.encrypt(MoneyTrackWeb.Endpoint, "mail-payload-v1", %{
        address: address,
        code: code
      })

    Repo.insert!(%Job{challenge_id: challenge.id, encrypted_payload: payload, available_at: now})
  end

  defp cancel_pending_mail(id) do
    Repo.update_all(from(j in Job, where: j.challenge_id == ^id and j.status == "queued"),
      set: [status: "cancelled", encrypted_payload: nil]
    )
  end

  defp transaction(fun), do: Repo.transaction(fun)
end
