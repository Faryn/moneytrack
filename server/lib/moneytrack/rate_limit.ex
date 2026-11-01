defmodule MoneyTrack.RateLimit do
  use Hammer, backend: :ets
end
