defmodule MoneyTrackWeb.SessionController do
  use MoneyTrackWeb, :controller
  alias MoneyTrack.{Accounts, Ledger}
  alias MoneyTrackWeb.Auth
  plug(:compatible_sync when action in [:sync_push, :sync_pull])

  def new(conn, _params), do: render(conn, :new, error: nil)

  def privacy(conn, _params) do
    notice =
      Application.app_dir(:moneytrack, privacy_resource()) |> File.read!() |> Jason.decode!()

    render(conn, :privacy, notice: notice, page_title: gettext("Privacy"))
  end

  defp privacy_resource do
    if MoneyTrackWeb.Language.current() == "de",
      do: "priv/privacy.de.json",
      else: "priv/privacy.json"
  end

  def create(conn, params) do
    with :ok <- Auth.allow_login(conn, params["username"]),
         {:ok, user} <- Accounts.authenticate(params["username"], params["password"]),
         {:ok, token, _session} <- Accounts.create_session(user, "browser", "Website") do
      Plug.CSRFProtection.delete_csrf_token()

      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(:session_token, token)
      |> redirect(to: ~p"/")
    else
      {:error, seconds} when is_integer(seconds) ->
        conn
        |> put_resp_header("retry-after", to_string(seconds))
        |> put_status(429)
        |> render(:new, error: gettext("Too many attempts. Please try again shortly."))

      _ ->
        conn
        |> put_status(401)
        |> render(:new, error: gettext("Username or password is incorrect."))
    end
  end

  def delete(conn, _params) do
    Plug.CSRFProtection.delete_csrf_token()
    if session = conn.assigns[:current_session], do: Accounts.revoke_session(session)
    conn |> configure_session(drop: true) |> redirect(to: ~p"/login")
  end

  def api_create(conn, params) do
    label = if is_binary(params["deviceName"]), do: params["deviceName"], else: "iPhone"

    with :ok <- Auth.allow_login(conn, params["username"]),
         {:ok, user} <- Accounts.authenticate(params["username"], params["password"]),
         {:ok, token, session} <- Accounts.create_session(user, "device", label) do
      json(conn, %{
        user: Accounts.identity(user),
        token: token,
        expiresAt: DateTime.to_iso8601(session.expires_at)
      })
    else
      {:error, seconds} when is_integer(seconds) ->
        conn
        |> put_resp_header("retry-after", to_string(seconds))
        |> put_status(429)
        |> json(%{
          error: "rate_limited",
          message: gettext("Too many attempts. Please try again shortly.")
        })

      _ ->
        conn
        |> put_status(401)
        |> json(%{
          error: "invalid_credentials",
          message: gettext("Username or password is incorrect.")
        })
    end
  end

  def api_show(conn, _), do: json(conn, %{user: Accounts.identity(conn.assigns.current_user)})

  def api_delete(conn, _) do
    Accounts.revoke_session(conn.assigns.current_session)
    send_resp(conn, 204, "")
  end

  def sync_push(conn, params) do
    case Ledger.apply_operation(conn.assigns.current_user, params) do
      {:ok, record} ->
        json(conn, %{record: record})

      {:error, {:conflict, current}} ->
        conn
        |> put_status(409)
        |> json(%{
          error: "revision_conflict",
          message: gettext("This item changed on another device. Review both versions."),
          current: current
        })

      {:error, :operation_reused} ->
        failure(
          conn,
          409,
          "operation_reused",
          "This saved request has different content. Review your changes."
        )

      {:error, :not_found} ->
        failure(
          conn,
          404,
          "not_found",
          "This item or its category is unavailable to this account."
        )

      {:error, {:validation, message}} ->
        failure(conn, 422, "validation_failed", message)

      {:error, _} ->
        failure(
          conn,
          422,
          "invalid_operation",
          gettext("Check this item's fields before trying again.")
        )
    end
  end

  def sync_pull(conn, params) do
    case Ledger.changes(conn.assigns.current_user, params["cursor"]) do
      {:ok, page} ->
        json(conn, page)

      {:error, _} ->
        failure(
          conn,
          400,
          "invalid_cursor",
          "Restart synchronization without discarding local changes."
        )
    end
  end

  defp compatible_sync(conn, _opts) do
    old_income =
      !String.starts_with?(conn.request_path, "/api/v5/") &&
        (Ledger.has_income?(conn.assigns.current_user) ||
           conn.params["payload"]["kind"] == "income")

    old_budget =
      (String.starts_with?(conn.request_path, "/api/v1/") ||
         String.starts_with?(conn.request_path, "/api/v2/")) &&
        (Ledger.has_budget_plan?(conn.assigns.current_user) ||
           conn.params["entity"] == "budget_plan")

    old_currency =
      !Enum.any?(["/api/v4/", "/api/v5/"], &String.starts_with?(conn.request_path, &1)) &&
        (Ledger.has_conversion?(conn.assigns.current_user) ||
           not is_nil(conn.params["payload"]["conversion"]))

    cond do
      old_income ->
        conn
        |> failure(
          426,
          "upgrade_required",
          "Update Spendie for income. Your pending changes are preserved."
        )
        |> halt()

      old_currency ->
        conn
        |> failure(
          426,
          "upgrade_required",
          "Update Spendie for currency conversion. Your pending changes are preserved."
        )
        |> halt()

      true ->
        check_budget_compatibility(conn, old_budget)
    end
  end

  defp check_budget_compatibility(conn, old_budget) do
    if old_budget do
      conn
      |> failure(
        426,
        "upgrade_required",
        "Update Spendie for whole-year budgets. Your pending changes are preserved."
      )
      |> halt()
    else
      compatible_sharing(conn)
    end
  end

  defp compatible_sharing(conn) do
    if String.starts_with?(conn.request_path, "/api/v1/") &&
         (MoneyTrack.Sharing.has_data?(conn.assigns.current_user) ||
            conn.params["entity"] in ["shared_expense", "shared_assignment", "repayment"]) do
      conn
      |> failure(
        426,
        "upgrade_required",
        "Update Spendie to sync shared activity. Your pending changes are preserved."
      )
      |> halt()
    else
      conn
    end
  end

  defp failure(conn, status, code, message),
    do:
      conn
      |> put_status(status)
      |> json(%{error: code, message: MoneyTrackWeb.Language.message(message)})
end
