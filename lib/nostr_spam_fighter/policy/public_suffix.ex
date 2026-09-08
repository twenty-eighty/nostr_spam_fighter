defmodule NostrSpamFighter.Policy.PublicSuffix do
  @moduledoc """
  Public Suffix List-aware registrable-domain handling.
  """

  @multi_part MapSet.new([
                "co.uk",
                "org.uk",
                "ac.uk",
                "gov.uk",
                "com.au",
                "net.au",
                "org.au",
                "co.nz",
                "com.br",
                "com.mx",
                "co.jp",
                "co.kr",
                "com.cn",
                "com.hk",
                "co.in",
                "com.sg",
                "com.tw",
                "co.za",
                "com.ar",
                "github.io",
                "blogspot.com"
              ])

  @spec registrable_domain(String.t()) :: String.t() | nil
  def registrable_domain(host) when is_binary(host) do
    host = String.downcase(host)

    if ip?(host) do
      host
    else
      labels = String.split(host, ".", trim: true)

      cond do
        length(labels) < 2 ->
          host

        true ->
          last_two = Enum.take(labels, -2) |> Enum.join(".")
          last_three = Enum.take(labels, -3) |> Enum.join(".")

          cond do
            MapSet.member?(@multi_part, last_two) and length(labels) >= 3 ->
              last_three

            MapSet.member?(@multi_part, last_three) and length(labels) >= 4 ->
              Enum.take(labels, -4) |> Enum.join(".")

            true ->
              last_two
          end
      end
    end
  end

  def registrable_domain(_), do: nil

  defp ip?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
