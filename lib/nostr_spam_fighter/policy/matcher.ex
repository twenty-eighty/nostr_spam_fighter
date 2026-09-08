defmodule NostrSpamFighter.Policy.Matcher do
  @moduledoc """
  Matches hostnames and URLs against the compiled policy.
  Never uses substring hostname matching.
  """

  alias NostrSpamFighter.Policy.{Cache, Normalizer, PublicSuffix}

  @spec match_target(String.t() | nil, String.t() | nil) :: [map()]
  def match_target(url, hostname) do
    host = hostname || (url && Normalizer.hostname_from_url(url))
    normalized_url = url && elem_ok(Normalizer.normalize_url(url))

    match_host_rules(host) ++
      match_domain_rules(host) ++
      Cache.match_url_prefixes(normalized_url)
  end

  defp match_host_rules(host) when is_binary(host), do: Cache.lookup("host", host)
  defp match_host_rules(_), do: []

  defp match_domain_rules(host) when is_binary(host) do
    host
    |> domain_candidates()
    |> Enum.flat_map(&Cache.lookup("domain", &1))
  end

  defp match_domain_rules(_), do: []

  # For host "ads.evil.com" => ["ads.evil.com", "evil.com", "com"]
  # Exact and parent labels cover domain rules without scanning all entries.
  defp domain_candidates(host) do
    labels = String.split(host, ".")

    for i <- 0..(length(labels) - 1) do
      labels |> Enum.drop(i) |> Enum.join(".")
    end
  end

  @doc """
  A domain rule matches the exact domain or a proper subdomain, never a substring host.
  """
  def domain_match?(host, domain) when is_binary(host) and is_binary(domain) do
    host == domain or String.ends_with?(host, "." <> domain)
  end

  def domain_match?(_, _), do: false

  def registrable_domain(host), do: PublicSuffix.registrable_domain(host)

  defp elem_ok({:ok, value}), do: value
  defp elem_ok(_), do: nil
end
