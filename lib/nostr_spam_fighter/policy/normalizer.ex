defmodule NostrSpamFighter.Policy.Normalizer do
  @moduledoc """
  Normalizes hosts, domains, and URLs for policy matching.
  """

  @spec normalize_host(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def normalize_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.downcase()
    |> String.trim_trailing(".")
    |> strip_brackets()
    |> strip_zone_id()
    |> idna_encode()
  end

  def normalize_host(_), do: {:error, :invalid_host}

  @spec normalize_url(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def normalize_url(url) when is_binary(url) do
    url =
      url
      |> String.trim()
      |> then(&Regex.replace(~r/[\\).,;:!?'"\]]+$/, &1, ""))

    with {:ok, uri} <- parse_http_uri(url),
         {:ok, host} <- normalize_host(uri.host) do
      path = uri.path || "/"
      query = if uri.query, do: "?" <> uri.query, else: ""
      port = explicit_port(uri)
      {:ok, "#{uri.scheme}://#{host}#{port}#{path}#{query}"}
    end
  end

  def normalize_url(_), do: {:error, :invalid_url}

  @spec hostname_from_url(String.t()) :: String.t() | nil
  def hostname_from_url(url) do
    case normalize_url(url) do
      {:ok, normalized} ->
        case URI.parse(normalized) do
          %URI{host: host} when is_binary(host) -> host
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp explicit_port(%URI{scheme: "http", port: port}) when port not in [nil, 80], do: ":#{port}"

  defp explicit_port(%URI{scheme: "https", port: port}) when port not in [nil, 443],
    do: ":#{port}"

  defp explicit_port(_), do: ""

  defp parse_http_uri(url) do
    uri = URI.parse(String.trim(url))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      {:ok, uri}
    else
      {:error, :invalid_url}
    end
  end

  defp strip_brackets("[" <> rest) do
    String.trim_trailing(rest, "]")
  end

  defp strip_brackets(host), do: host

  defp strip_zone_id(host) do
    case String.split(host, "%", parts: 2) do
      [addr, _zone] -> addr
      [addr] -> addr
    end
  end

  defp idna_encode(""), do: {:error, :invalid_host}

  defp idna_encode(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, addr} ->
        {:ok, ip_to_string(addr)}

      {:error, :einval} ->
        if ascii_hostname?(host) do
          {:ok, host}
        else
          punycode_encode(host)
        end
    end
  end

  defp ascii_hostname?(host) when host == <<>>, do: false
  defp ascii_hostname?(host), do: ascii_host_bytes?(host)

  defp ascii_host_bytes?(<<>>), do: true

  defp ascii_host_bytes?(<<c, rest::binary>>)
       when c in ?a..?z or c in ?0..?9 or c in [?., ?-, ?_],
       do: ascii_host_bytes?(rest)

  defp ascii_host_bytes?(_), do: false

  defp punycode_encode(host) do
    try do
      encoded =
        :idna.encode(String.to_charlist(host), uts46: true, std3_rules: false)

      {:ok, List.to_string(encoded)}
    rescue
      _ -> fallback_host(host)
    catch
      :exit, _ -> fallback_host(host)
    end
  end

  defp fallback_host(host) do
    if usable_hostname?(host), do: {:ok, host}, else: {:error, :invalid_host}
  end

  defp usable_hostname?(host) do
    host != "" and String.valid?(host) and not String.contains?(host, [" ", "\t"])
  end

  defp ip_to_string(addr) do
    addr
    |> :inet.ntoa()
    |> List.to_string()
    |> String.downcase()
  end
end
