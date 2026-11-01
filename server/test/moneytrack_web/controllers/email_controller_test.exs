defmodule MoneyTrackWeb.EmailControllerTest do
  use MoneyTrackWeb.ConnCase
  import MoneyTrack.Fixtures
  alias MoneyTrack.Accounts

  test "only authenticated account sees and verifies its email", %{conn: conn} do
    assert conn |> get("/api/v1/account/email") |> json_response(401)
    owner = user()
    {:ok, token, _} = Accounts.create_session(owner, "device", "test")
    authed = fn -> conn |> put_req_header("authorization", "Bearer " <> token) end
    id = Ecto.UUID.generate()

    assert %{"verificationID" => ^id, "verifiedEmail" => nil} =
             authed.()
             |> post("/api/v1/account/email", %{email: "owner@example.org", requestID: id})
             |> json_response(200)

    MoneyTrack.MailDelivery.deliver_pending()
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is ([0-9]{8})/, mail.text_body)

    assert %{"verifiedEmail" => "owner@example.org"} =
             authed.()
             |> post("/api/v1/account/email/verify", %{verificationID: id, code: code})
             |> json_response(200)

    assert %{"verifiedEmail" => "owner@example.org"} =
             authed.() |> get("/api/v1/account/email") |> json_response(200)

    {:ok, other_token, _} = Accounts.create_session(user(), "device", "other")

    assert %{"verifiedEmail" => nil} =
             conn
             |> put_req_header("authorization", "Bearer " <> other_token)
             |> get("/api/v1/account/email")
             |> json_response(200)
  end
end
