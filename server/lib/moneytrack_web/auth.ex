defmodule MoneyTrackWeb.Auth do
  use Gettext, backend: MoneyTrackWeb.Gettext
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView, except: [redirect: 2]
  alias MoneyTrack.Accounts

  def require_api(conn, _opts) do
    with [<<scheme::binary-size(6), " ", token::binary>>] <- get_req_header(conn, "authorization"),
         true <- String.downcase(scheme) == "bearer",
         {:ok, user, session} <- Accounts.fetch_session(token, "device") do
      conn |> assign(:current_user, user) |> assign(:current_session, session)
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "unauthorized", message: gettext("Sign in to continue syncing.")})
        |> halt()
    end
  end

  def fetch_browser(conn, _opts) do
    case Accounts.fetch_session(get_session(conn, :session_token), "browser") do
      {:ok, user, session} ->
        conn |> assign(:current_user, user) |> assign(:current_session, session)

      :error ->
        assign(conn, :current_user, nil)
    end
  end

  def require_browser(conn, _opts) do
    if conn.assigns[:current_user], do: conn, else: conn |> redirect(to: "/login") |> halt()
  end

  def allow_login(conn, username) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    identity = :crypto.hash(:sha256, MoneyTrack.Accounts.User.normalize_username(username))

    with {:allow, _} <- MoneyTrack.RateLimit.hit({:login_ip, ip}, 60_000, 60),
         {:allow, _} <- MoneyTrack.RateLimit.hit({:login_user, identity}, 60_000, 10) do
      :ok
    else
      {:deny, milliseconds} -> {:error, max(1, div(milliseconds + 999, 1000))}
    end
  end

  def on_mount(:required, _params, session, socket) do
    case Accounts.fetch_session(session["session_token"], "browser") do
      {:ok, user, session} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(MoneyTrack.PubSub, "session:#{session.id}")

          Process.send_after(
            self(),
            :session_revoked,
            max(0, DateTime.diff(session.expires_at, DateTime.utc_now(), :millisecond))
          )
        end

        socket =
          socket
          |> Phoenix.Component.assign(:current_user, user)
          |> attach_hook(:session_revocation, :handle_info, fn
            :session_revoked, socket -> {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
            _message, socket -> {:cont, socket}
          end)

        {:cont, socket}

      :error ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end
end
