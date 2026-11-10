defmodule MoneyTrackWeb.EmailLive do
  use MoneyTrackWeb, :live_view
  alias MoneyTrack.Accounts.EmailVerification

  @impl true
  def mount(_, _, socket) do
    status = EmailVerification.status(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       status: status,
       request_id: Ecto.UUID.generate(),
       error: nil,
       email_form: to_form(%{"address" => status.pendingEmail || ""}, as: :email),
       code_form: to_form(%{"code" => ""}, as: :verification)
     )}
  end

  @impl true
  def handle_event("request", %{"email" => %{"address" => address}}, socket) do
    result =
      EmailVerification.request(socket.assigns.current_user, address, socket.assigns.request_id)

    {:noreply,
     socket |> assign(email_form: to_form(%{"address" => address}, as: :email)) |> result(result)}
  end

  def handle_event("verify", %{"verification" => %{"code" => code}}, socket) do
    result =
      EmailVerification.verify(
        socket.assigns.current_user,
        socket.assigns.status.verificationID,
        code
      )

    {:noreply, result(socket, result)}
  end

  defp result(socket, {:ok, status}),
    do:
      assign(socket,
        status: status,
        error: nil,
        request_id: Ecto.UUID.generate(),
        code_form: to_form(%{"code" => ""}, as: :verification)
      )

  defp result(socket, {:error, reason}),
    do:
      assign(socket,
        error: reason |> EmailVerification.message() |> MoneyTrackWeb.Language.message(),
        status: EmailVerification.status(socket.assigns.current_user)
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{user: @current_user}}>
      <.link navigate={~p"/"} class="link">{gettext("Back to Budget")}</.link>
      <h1 class="text-2xl font-semibold">{gettext("Email for Sharing")}</h1>
      <p class="text-base-content/70">
        {gettext(
          "Verify mailbox ownership for sharing invitations. Keep signing in with your username and password. Email isn't used for password recovery."
        )}
      </p>
      <div :if={@status.verifiedEmail} id="verified-email" class="alert border-success">
        <.icon name="hero-check-badge" />
        <span>{gettext("Verified: %{email}", email: @status.verifiedEmail)}</span>
      </div>
      <div :if={!@status.verifiedEmail}>
        <.form for={@email_form} id="email-form" phx-submit="request">
          <.input
            field={@email_form[:address]}
            type="email"
            label={gettext("Email address")}
            autocomplete="email"
            required
          />
          <.button phx-disable-with={gettext("Sending…")}>{if @status.verificationID,
            do: gettext("Send New Code"),
            else: gettext("Send Verification Code")}</.button>
        </.form>
        <.form
          :if={@status.verificationID}
          for={@code_form}
          id="verification-form"
          phx-submit="verify"
          class="mt-6"
        >
          <p>
            {gettext(
              "Enter the eight-digit code sent to %{email}. It expires after 30 minutes and allows five attempts. Only the newest code works.",
              email: @status.pendingEmail
            )}
          </p>
          <.input
            field={@code_form[:code]}
            type="text"
            label={gettext("Verification code")}
            inputmode="numeric"
            autocomplete="one-time-code"
            minlength="8"
            maxlength="8"
            pattern="[0-9]{8}"
            required
          />
          <.button phx-disable-with={gettext("Verifying…")}>{gettext("Verify Email")}</.button>
        </.form>
      </div>
      <p :if={@error} id="email-error" role="alert" class="text-error">{@error}</p>
    </Layouts.app>
    """
  end
end
