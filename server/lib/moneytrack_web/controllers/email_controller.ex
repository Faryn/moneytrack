defmodule MoneyTrackWeb.EmailController do
  use MoneyTrackWeb, :controller
  alias MoneyTrack.Accounts.EmailVerification
  def show(conn, _), do: json(conn, EmailVerification.status(conn.assigns.current_user))

  def create(conn, params),
    do:
      respond(
        conn,
        EmailVerification.request(conn.assigns.current_user, params["email"], params["requestID"])
      )

  def verify(conn, params),
    do:
      respond(
        conn,
        EmailVerification.verify(
          conn.assigns.current_user,
          params["verificationID"],
          params["code"]
        )
      )

  defp respond(conn, {:ok, result}), do: json(conn, result)

  defp respond(conn, {:error, reason}) do
    status =
      case reason do
        :rate_limited -> 429
        :delivery_unavailable -> 503
        reason when reason in [:already_verified, :address_unavailable, :invalid_request] -> 409
        _ -> 422
      end

    conn
    |> put_status(status)
    |> json(%{error: to_string(reason), message: EmailVerification.message(reason)})
  end
end
