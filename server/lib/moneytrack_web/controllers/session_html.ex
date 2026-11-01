defmodule MoneyTrackWeb.SessionHTML do
  use MoneyTrackWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-sm space-y-6">
        <h1 class="text-3xl font-semibold">Sign in</h1>
        <p :if={@error} role="alert" class="text-error">{@error}</p>
        <.form :let={f} for={%{}} action={~p"/login"} class="space-y-4" id="login-form">
          <.input field={f[:username]} label="Username" autocomplete="username" required />
          <.input
            field={f[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <button type="submit" class="btn btn-primary w-full">Sign In</button>
        </.form>
        <p class="text-sm text-base-content/70">Accounts are created by the administrator.</p>
      </section>
    </Layouts.app>
    """
  end
end
