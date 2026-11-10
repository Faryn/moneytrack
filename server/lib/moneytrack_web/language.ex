defmodule MoneyTrackWeb.Language do
  @moduledoc "Selects English or German for browser, LiveView, and API responses."

  import Plug.Conn

  @backend MoneyTrackWeb.Gettext

  def call(conn, _opts) do
    locale = conn |> get_req_header("accept-language") |> negotiate()
    Gettext.put_locale(@backend, locale)

    conn
    |> assign(:locale, locale)
    |> put_resp_header("content-language", locale)
  end

  def init(opts), do: opts

  def live_session(conn), do: %{"locale" => conn.assigns.locale}

  def on_mount(:default, _params, session, socket) do
    Gettext.put_locale(@backend, if(session["locale"] == "de", do: "de", else: "en"))
    {:cont, socket}
  end

  def current, do: Gettext.get_locale(@backend)

  def message(text), do: Gettext.gettext(@backend, text)

  def date(value) do
    if current() == "de", do: Calendar.strftime(value, "%d.%m.%Y"), else: Date.to_iso8601(value)
  end

  def money(cents) do
    sign = if cents < 0, do: "−", else: ""
    amount = abs(cents)
    fraction = amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    whole = div(amount, 100)

    if current() == "de",
      do: "#{sign}#{whole},#{fraction} €",
      else: "#{sign}€#{whole}.#{fraction}"
  end

  defp negotiate(headers) do
    headers
    |> Enum.join(",")
    |> String.split(",")
    |> Enum.map(&preference/1)
    |> Enum.filter(fn {locale, quality} -> locale in ["de", "en"] and quality > 0 end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> List.first({"en", 1})
    |> elem(0)
  end

  defp preference(value) do
    [tag | params] = String.split(value, ";")
    locale = tag |> String.trim() |> String.downcase() |> String.split("-", parts: 2) |> hd()

    quality =
      Enum.find_value(params, 1, fn param ->
        case String.trim(param) do
          "q=" <> weight ->
            case Float.parse(weight) do
              {q, ""} when q >= 0 and q <= 1 -> q
              _ -> 0
            end

          _ ->
            nil
        end
      end)

    {locale, quality}
  end
end
