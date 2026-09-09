defmodule NostrSpamFighter.Policy.Matcher do
  @moduledoc """
  Matches hostnames against the compiled policy by **registrable domain**.

  A listed domain blocks that domain and all of its subdomains (the domain
  owner is treated as responsible for subdomain content). Exact host and
  URL-prefix rules are not kept in the hot cache.
  """

  alias NostrSpamFighter.Policy.{Cache, Normalizer, PublicSuffix}

  @spec match_target(String.t() | nil, String.t() | nil) :: [map()]
  def match_target(url, hostname) do
    host = hostname || (url && Normalizer.hostname_from_url(url))

    case host && PublicSuffix.registrable_domain(host) do
      domain when is_binary(domain) and domain != "" ->
        Cache.lookup_domain(domain)

      _ ->
        []
    end
  end

  @doc """
  A domain rule matches the exact domain or a proper subdomain, never a substring host.
  Kept for tests / callers that reason about domain trees explicitly.
  """
  def domain_match?(host, domain) when is_binary(host) and is_binary(domain) do
    host == domain or String.ends_with?(host, "." <> domain)
  end

  def domain_match?(_, _), do: false

  def registrable_domain(host), do: PublicSuffix.registrable_domain(host)
end
