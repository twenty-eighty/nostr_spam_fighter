defmodule NostrSpamFighter.Scanner.AddressValidator do
  @moduledoc """
  SSRF address validation. Rejects non-public destinations before every connection.
  """

  alias NostrSpamFighter.Policy.Normalizer

  @type destination :: %{
          scheme: String.t(),
          host: String.t(),
          port: pos_integer(),
          ips: [:inet.ip_address()]
        }

  @spec validate_url(String.t(), keyword()) :: {:ok, destination()} | {:error, atom()}
  def validate_url(url, opts \\ []) do
    with {:ok, uri} <- parse_uri(url),
         {:ok, host} <- Normalizer.normalize_host(uri.host),
         {:ok, ips} <- resolve_host(host),
         :ok <- reject_non_public(ips, opts) do
      {:ok,
       %{
         scheme: uri.scheme,
         host: host,
         port: uri.port || default_port(uri.scheme),
         ips: ips
       }}
    end
  end

  @spec public_ip?(:inet.ip_address()) :: boolean()
  def public_ip?(ip), do: public_ip?(ip, [])

  def public_ip?(ip, opts) do
    allow_loopback? = Keyword.get(opts, :allow_loopback?, false)
    ip = unwrap_v4_mapped(ip)

    cond do
      allow_loopback? and loopback?(ip) -> true
      unspecified?(ip) -> false
      loopback?(ip) -> false
      private?(ip) -> false
      link_local?(ip) -> false
      multicast?(ip) -> false
      documentation?(ip) -> false
      benchmarking?(ip) -> false
      reserved?(ip) -> false
      unique_local?(ip) -> false
      metadata?(ip) -> false
      true -> true
    end
  end

  def resolve_host(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, :einval} ->
        case :inet.getaddrs(String.to_charlist(host), :inet) do
          {:ok, v4} ->
            v6 =
              case :inet.getaddrs(String.to_charlist(host), :inet6) do
                {:ok, addrs} -> addrs
                _ -> []
              end

            {:ok, Enum.uniq(v4 ++ v6)}

          {:error, _} ->
            case :inet.getaddrs(String.to_charlist(host), :inet6) do
              {:ok, addrs} -> {:ok, addrs}
              {:error, _} -> {:error, :dns_failure}
            end
        end
    end
  end

  defp parse_uri(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] -> {:error, :unsupported_scheme}
      not is_binary(uri.host) or uri.host == "" -> {:error, :invalid_url}
      String.contains?(uri.host, "%") -> {:error, :invalid_url}
      true -> {:ok, uri}
    end
  end

  defp default_port("https"), do: 443
  defp default_port(_), do: 80

  defp reject_non_public(ips, opts) do
    if Enum.any?(ips, &(not public_ip?(&1, opts))) do
      {:error, :blocked_address}
    else
      :ok
    end
  end

  defp unwrap_v4_mapped({0, 0, 0, 0, 0, 65_535, a, b}) do
    <<a1, a2>> = <<a::16>>
    <<b1, b2>> = <<b::16>>
    {a1, a2, b1, b2}
  end

  defp unwrap_v4_mapped(ip), do: ip

  defp unspecified?({0, 0, 0, 0}), do: true
  defp unspecified?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp unspecified?(_), do: false

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp private?({10, _, _, _}), do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp private?({100, b, _, _}) when b >= 64 and b <= 127, do: true
  defp private?(_), do: false

  defp link_local?({169, 254, _, _}), do: true
  defp link_local?({0xFE80, _, _, _, _, _, _, _}), do: true
  defp link_local?(_), do: false

  defp unique_local?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true
  defp unique_local?(_), do: false

  defp multicast?({a, _, _, _}) when a >= 224 and a <= 239, do: true
  defp multicast?({a, _, _, _, _, _, _, _}) when a >= 0xFF00, do: true
  defp multicast?(_), do: false

  defp documentation?({192, 0, 2, _}), do: true
  defp documentation?({198, 51, 100, _}), do: true
  defp documentation?({203, 0, 113, _}), do: true
  defp documentation?({0x2001, 0xDB8, _, _, _, _, _, _}), do: true
  defp documentation?(_), do: false

  defp benchmarking?({198, 18, _, _}), do: true
  defp benchmarking?({198, 19, _, _}), do: true
  defp benchmarking?(_), do: false

  defp reserved?({0, _, _, _}), do: true
  defp reserved?({240, _, _, _}), do: true
  defp reserved?({255, 255, 255, 255}), do: true
  defp reserved?(_), do: false

  defp metadata?({169, 254, 169, 254}), do: true
  defp metadata?(_), do: false
end
