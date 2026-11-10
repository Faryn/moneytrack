defmodule MoneyTrack.Currency do
  @moduledoc "Exact conversion from published foreign units per EUR; saved conversions never reprice."
  @currencies ~w(AUD BRL CAD CHF CNY CZK DKK GBP HKD HUF IDR ILS INR ISK JPY KRW MXN MYR NOK NZD PHP PLN RON SEK SGD THB TRY USD ZAR)
  def currencies, do: @currencies
  def digits(code), do: if(code in ~w(ISK JPY KRW), do: 0, else: 2)

  def euro_cents(
        %{
          "originalAmount" => original,
          "originalCurrency" => code,
          "rate" => rate,
          "rateDate" => date,
          "source" => "ECB"
        } = value
      ) do
    with true <-
           Enum.sort(Map.keys(value)) ==
             Enum.sort(~w(originalAmount originalCurrency rate rateDate source)),
         true <- is_integer(original) and original in 1..99_999_999_999,
         true <- code in @currencies,
         true <- is_binary(rate) and Regex.match?(~r/^[0-9]{1,8}(\.[0-9]{1,8})?$/, rate),
         true <- is_binary(date),
         {:ok, _} <- Date.from_iso8601(date),
         {numerator, scale} <- rational(rate),
         true <- numerator > 0 do
      denominator = Integer.pow(10, digits(code)) * numerator
      cents = div(original * 100 * scale * 2 + denominator, denominator * 2)
      if cents in 1..99_999_999_999, do: {:ok, cents}, else: {:error, :invalid_conversion}
    else
      _ -> {:error, :invalid_conversion}
    end
  end

  def euro_cents(_), do: {:error, :invalid_conversion}
  def validate!(nil, _amount), do: nil

  def validate!(conversion, amount) do
    case euro_cents(conversion) do
      {:ok, ^amount} ->
        conversion

      _ ->
        MoneyTrack.Repo.rollback(
          {:validation, "The original amount, exchange rate and euro amount must agree."}
        )
    end
  end

  defp rational(rate) do
    case String.split(rate, ".") do
      [whole] ->
        {String.to_integer(whole), 1}

      [whole, fraction] ->
        {String.to_integer(whole <> fraction), Integer.pow(10, String.length(fraction))}
    end
  end

  def parse(value) when is_binary(value) do
    value = value |> String.trim() |> String.replace(",", ".")

    if Regex.match?(~r/\A[0-9]+(\.[0-9]{1,2})?\z/, value) do
      [whole | fraction] = String.split(value, ".")

      fraction =
        case fraction do
          [] -> 0
          [v] -> v |> String.pad_trailing(2, "0") |> String.to_integer()
        end

      amount = String.to_integer(whole) * 100 + fraction
      if amount in 1..99_999_999_999, do: {:ok, amount}, else: :error
    else
      :error
    end
  end

  def parse(_), do: :error

  def original_input(conversion) do
    amount = conversion["originalAmount"]

    if digits(conversion["originalCurrency"]) == 0,
      do: Integer.to_string(amount),
      else:
        "#{div(amount, 100)}.#{amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  def rates do
    key = {__MODULE__, :rates}
    cached = :persistent_term.get(key, nil)
    now = System.monotonic_time(:second)

    if cached && now - cached.fetched < 900 do
      {:ok, cached}
    else
      result =
        with {:ok, %{status: 200, body: body}} when is_binary(body) <-
               Req.get("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml",
                 decode_body: false,
                 receive_timeout: 10_000,
                 retry: false
               ),
             {:ok, rates} <- decode_rates(body),
             do: {:ok, Map.put(rates, :fetched, now)}

      case result do
        {:ok, rates} ->
          :persistent_term.put(key, rates)
          {:ok, rates}

        _ when not is_nil(cached) ->
          {:ok, cached}

        _ ->
          {:error, "Exchange rates are unavailable. Try again when connected."}
      end
    end
  end

  def decode_rates(body) when byte_size(body) < 100_000 do
    with [_, date] <- Regex.run(~r/time=['"]([0-9-]+)['"]/, body),
         {:ok, _} <- Date.from_iso8601(date) do
      rates =
        Regex.scan(~r/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/, body)
        |> Enum.filter(fn [_, code, _] -> code in @currencies end)
        |> Map.new(fn [_, code, rate] -> {code, rate} end)

      if map_size(rates) > 0,
        do: {:ok, %{date: date, rates: rates}},
        else: {:error, :invalid_rates}
    else
      _ -> {:error, :invalid_rates}
    end
  end

  def decode_rates(_), do: {:error, :invalid_rates}

  def from_input(input, code, old \\ nil) do
    code = if code in [nil, ""], do: "EUR", else: code

    with {:ok, cents} <- parse(input),
         true <- code == "EUR" || code in @currencies do
      if code == "EUR" do
        {:ok, cents, nil}
      else
        if digits(code) == 0 && rem(cents, 100) != 0 do
          {:error, "This currency does not use fractional units."}
        else
          original = if digits(code) == 0, do: div(cents, 100), else: cents

          if old && old["originalAmount"] == original && old["originalCurrency"] == code do
            case euro_cents(old) do
              {:ok, euro} -> {:ok, euro, old}
              _ -> {:error, "Invalid saved conversion."}
            end
          else
            with {:ok, snapshot} <- rates(),
                 rate when is_binary(rate) <- snapshot.rates[code] do
              conversion = %{
                "originalAmount" => original,
                "originalCurrency" => code,
                "rate" => rate,
                "rateDate" => snapshot.date,
                "source" => "ECB"
              }

              case euro_cents(conversion) do
                {:ok, euro} -> {:ok, euro, conversion}
                _ -> {:error, "Check the original amount and exchange rate."}
              end
            else
              _ -> {:error, "Exchange rates are unavailable for this currency."}
            end
          end
        end
      end
    else
      _ -> {:error, "Enter a valid amount and currency."}
    end
  end
end
