defmodule MoneyTrackWeb.HealthController do
  use MoneyTrackWeb, :controller

  # Liveness only. No financial data or configuration is exposed here.
  def show(conn, _params), do: json(conn, %{status: "ok"})
end
