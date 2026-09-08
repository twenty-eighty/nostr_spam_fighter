defmodule NostrSpamFighter.Policy.Matcher do
  @moduledoc """
  Matches hostnames and URLs against the compiled policy.
  Never uses substring hostname matching.
  """

  alias NostrSpamFighter.Policy.{Cache, Normalizer, PublicSuffix}

  @spec match_target(String.t() | nil, String.t() | nil) :: [map()]
  def match_target(url, hostname) do
    rules = Cache.rules()
    host = hostname || (url && Normalizer.hostname_from_url(url))
    normalized_url = url && elem_ok(Normalizer.normalize_url(url))

    Enum.flat_map(rules, fn rule ->
      if matches_rule?(rule, normalized_url, host), do: [rule], else: []
    end)
  end

  defp matches_rule?(%{rule_type: "host", normalized_value: value}, _url, host)
       when is_binary(host) do
    host == value
  end

  defp matches_rule?(%{rule_type: "domain", normalized_value: value}, _url, host)
       when is_binary(host) do
    domain_match?(host, value)
  end

  defp matches_rule?(%{rule_type: "url_prefix", normalized_value: value}, url, _host)
       when is_binary(url) do
    String.starts_with?(url, value)
  end

  defp matches_rule?(_, _, _), do: false

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
