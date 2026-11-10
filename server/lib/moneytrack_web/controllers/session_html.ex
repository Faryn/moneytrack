defmodule MoneyTrackWeb.SessionHTML do
  use MoneyTrackWeb, :html

  def privacy(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <article id="privacy-notice" class="space-y-8">
        <header class="space-y-3">
          <h1 class="text-3xl font-semibold">{@notice["title"]}</h1>
          <p class="text-sm text-base-content/70">
            {gettext("Updated %{date}", date: @notice["updated"])}
          </p>
          <p class="leading-relaxed">{@notice["summary"]}</p>
        </header>
        <section :for={part <- @notice["sections"]} id={"privacy-" <> part["id"]} class="space-y-3">
          <h2 class="text-xl font-semibold">{part["title"]}</h2>
          <p :for={paragraph <- part["paragraphs"]} class="leading-relaxed">{paragraph}</p>
          <ul :if={part["links"]} class="space-y-2">
            <li :for={reference <- part["links"]}>
              <a href={reference["url"]} class="link link-primary">{reference["title"]}</a>
            </li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-sm space-y-6">
        <h1 class="text-3xl font-semibold">{gettext("Sign in")}</h1>
        <p :if={@error} role="alert" class="text-error">{@error}</p>
        <.form :let={f} for={%{}} action={~p"/login"} class="space-y-4" id="login-form">
          <.input field={f[:username]} label={gettext("Username")} autocomplete="username" required />
          <.input
            field={f[:password]}
            type="password"
            label={gettext("Password")}
            autocomplete="current-password"
            required
          />
          <button type="submit" class="btn btn-primary w-full">{gettext("Sign In")}</button>
        </.form>
        <p class="text-sm text-base-content/70">
          {gettext("Accounts are created by the administrator.")}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
