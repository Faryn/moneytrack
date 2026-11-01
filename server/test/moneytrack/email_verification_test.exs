defmodule MoneyTrack.EmailVerificationTest do
  use MoneyTrack.DataCase
  alias MoneyTrack.Accounts.{EmailVerification, EmailChallenge, VerifiedEmail}
  alias MoneyTrack.MailDelivery.Job
  import MoneyTrack.Fixtures

  defp request(user, address \\ "person@example.org") do
    id = Ecto.UUID.generate()
    assert {:ok, %{verificationID: ^id}} = EmailVerification.request(user, address, id)
    {id, Repo.get_by!(Job, challenge_id: id)}
  end

  defp code do
    MoneyTrack.MailDelivery.deliver_pending()
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is ([0-9]{8})/, mail.text_body)
    {code, mail}
  end

  test "proof is bound to account, emailed code, and normalized unique address" do
    owner = user()
    other = user()
    {id, job} = request(owner, "  Person@Example.ORG ")
    assert job.status == "queued"
    assert EmailVerification.status(owner).verifiedEmail == nil
    {code, mail} = code()
    assert mail.to == [{"", "person@example.org"}]
    refute String.contains?(job.encrypted_payload, code)
    assert Repo.get!(Job, job.id).encrypted_payload == nil
    assert {:error, :invalid_code} = EmailVerification.verify(other, id, code)
    assert Repo.get!(EmailChallenge, id).attempts == 0

    assert {:ok, %{verifiedEmail: "person@example.org", verificationID: nil}} =
             EmailVerification.verify(owner, id, code)

    assert {:error, :invalid_code} = EmailVerification.verify(owner, id, code)
    assert Repo.aggregate(VerifiedEmail, :count) == 1
    {second, _} = request(other)
    {another_code, _} = code()
    assert {:error, :address_unavailable} = EmailVerification.verify(other, second, another_code)
    assert EmailVerification.status(other).verifiedEmail == nil

    assert {:error, :already_verified} =
             EmailVerification.request(owner, "new@example.org", Ecto.UUID.generate())
  end

  test "five failed attempts survive transaction commits; expiry prevents acceptance and delivery" do
    owner = user()
    {id, _} = request(owner)
    {code, _} = code()
    wrong = if code == "00000000", do: "11111111", else: "00000000"

    for _ <- 1..5,
        do: assert({:error, :invalid_code} = EmailVerification.verify(owner, id, wrong))

    assert Repo.get!(EmailChallenge, id).attempts == 5
    assert {:error, :invalid_code} = EmailVerification.verify(owner, id, code)
    assert EmailVerification.status(owner).verificationID == nil
    {expired_id, job} = request(owner)

    Repo.get!(EmailChallenge, expired_id)
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()

    assert {:error, :invalid_code} = EmailVerification.verify(owner, expired_id, code)
    MoneyTrack.MailDelivery.deliver_pending()
    refute_receive {:email, _}
    assert Repo.get!(Job, job.id).status == "cancelled"
    assert Repo.get!(Job, job.id).encrypted_payload == nil
  end

  test "retry has one challenge and delivery; replacement retires old code; request quota persists" do
    owner = user()
    {id, first_job} = request(owner)

    assert {:ok, %{verificationID: ^id}} =
             EmailVerification.request(owner, "person@example.org", id)

    assert Repo.aggregate(Job, :count) == 1

    assert {:error, :invalid_request} =
             EmailVerification.request(user(), "person@example.org", id)

    {second, _} = request(owner)
    assert Repo.get!(Job, first_job.id).status == "cancelled"
    assert Repo.get!(EmailChallenge, id).retired_at
    {code, _} = code()
    assert {:error, :invalid_code} = EmailVerification.verify(owner, id, code)

    assert {:ok, %{verifiedEmail: "person@example.org"}} =
             EmailVerification.verify(owner, second, code)

    another = user()
    for _ <- 1..3, do: request(another)

    assert {:error, :rate_limited} =
             EmailVerification.request(another, "person@example.org", Ecto.UUID.generate())

    assert Repo.aggregate(from(c in EmailChallenge, where: c.user_id == ^another.id), :count) == 3
  end

  test "mail lease survives worker restart and retry reuses code and message ID" do
    owner = user()
    {id, job} = request(owner)

    job
    |> Ecto.Changeset.change(
      status: "sending",
      attempts: 1,
      available_at: DateTime.add(DateTime.utc_now(), -1, :second)
    )
    |> Repo.update!()

    {code, mail} = code()
    assert mail.headers["Message-ID"] == "<#{job.id}@moneytrack.invalid>"
    assert Repo.get!(Job, job.id).status == "sent"
    assert Repo.get!(Job, job.id).attempts == 2
    assert {:ok, _} = EmailVerification.verify(owner, id, code)
    MoneyTrack.MailDelivery.deliver_pending()
    refute_receive {:email, _}
  end

  test "request and mail are rolled back together; malformed addresses are rejected" do
    owner = user()
    id = Ecto.UUID.generate()

    assert {:error, :test_rollback} =
             Repo.transaction(fn ->
               assert {:ok, _} = EmailVerification.request(owner, "person@example.org", id)
               Repo.rollback(:test_rollback)
             end)

    assert Repo.aggregate(Job, :count) == 0
    assert Repo.aggregate(EmailChallenge, :count) == 0

    for address <- [
          nil,
          "person",
          "a@example.org\r\nBcc: b@example.org",
          "A Name <a@example.org>",
          ".a@example.org",
          "a..b@example.org",
          "a@bad..org",
          "a@-bad.org"
        ] do
      assert {:error, :invalid_email} =
               EmailVerification.request(owner, address, Ecto.UUID.generate())
    end
  end

  defmodule FailingAdapter do
    use Swoosh.Adapter
    def deliver(_email, _config), do: {:error, :simulated_provider_failure}
  end

  test "provider failure retries durably and clears encrypted payload after terminal failure" do
    owner = user()
    {_id, job} = request(owner)
    config = Application.fetch_env!(:moneytrack, MoneyTrack.Mailer)
    on_exit(fn -> Application.put_env(:moneytrack, MoneyTrack.Mailer, config) end)
    Application.put_env(:moneytrack, MoneyTrack.Mailer, adapter: FailingAdapter)
    MoneyTrack.MailDelivery.deliver_pending()
    retry = Repo.get!(Job, job.id)
    assert retry.status == "queued"
    assert retry.attempts == 1
    assert retry.encrypted_payload == job.encrypted_payload
    assert DateTime.compare(retry.available_at, DateTime.utc_now()) == :gt

    retry
    |> Ecto.Changeset.change(
      attempts: 4,
      available_at: DateTime.add(DateTime.utc_now(), -1, :second)
    )
    |> Repo.update!()

    MoneyTrack.MailDelivery.deliver_pending()
    failed = Repo.get!(Job, job.id)
    assert failed.status == "failed"
    assert failed.attempts == 5
    assert failed.encrypted_payload == nil
    refute_receive {:email, _}
  end

  test "bad identifiers are rate limited in the shared context, before hashing" do
    owner = user()

    for _ <- 1..20 do
      assert {:error, :invalid_code} =
               EmailVerification.verify(owner, Ecto.UUID.generate(), "12345678")
    end

    assert {:error, :rate_limited} =
             EmailVerification.verify(owner, Ecto.UUID.generate(), "12345678")
  end
end
