defmodule MoneyTrackWeb.EmailLiveTest do
  use MoneyTrackWeb.ConnCase
  import Phoenix.LiveViewTest

  test "browser verifies address with the same ownership context", %{conn: conn} do
    owner = MoneyTrack.Fixtures.user()
    {:ok, token, _} = MoneyTrack.Accounts.create_session(owner, "browser", "test")
    {:ok, view, _} = live(init_test_session(conn, %{session_token: token}), "/account/email")
    view |> form("#email-form", email: %{address: "browser@example.org"}) |> render_submit()
    assert has_element?(view, "#verification-form")
    MoneyTrack.MailDelivery.deliver_pending()
    assert_receive {:email, mail}
    [_, code] = Regex.run(~r/code is ([0-9]{8})/, mail.text_body)
    view |> form("#verification-form", verification: %{code: code}) |> render_submit()
    assert has_element?(view, "#verified-email", "browser@example.org")
    refute has_element?(view, "#email-form")
    {:ok, restored, _} = live(init_test_session(conn, %{session_token: token}), "/account/email")
    assert has_element?(restored, "#verified-email", "browser@example.org")
  end
end
