defmodule NostrSpamFighter.Moderation.TargetState do
  @moduledoc """
  Live policy lookup for a domain or URL, shaped like article moderation results.

  URL lookups follow redirects (same as article scans) and match policy on every hop.
  """

  import Ecto.Query

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{Cache, Category, Matcher, Normalizer, PublicSuffix}
  alias NostrSpamFighter.Scanner.RedirectResolver

  @spec lookup_domain(String.t()) :: {:ok, map()} | {:error, :invalid_domain}
  def lookup_domain(domain) when is_binary(domain) do
    with {:ok, host} <- Normalizer.normalize_host(domain),
         registrable when is_binary(registrable) and registrable != "" <-
           PublicSuffix.registrable_domain(host) do
      matches = Matcher.match_target(nil, host)
      {:ok, present_domain(host, registrable, matches)}
    else
      _ -> {:error, :invalid_domain}
    end
  end

  def lookup_domain(_), do: {:error, :invalid_domain}

  @spec lookup_url(String.t()) :: {:ok, map()} | {:error, :invalid_url}
  def lookup_url(url) when is_binary(url) do
    with {:ok, normalized} <- Normalizer.normalize_url(url),
         host when is_binary(host) <- Normalizer.hostname_from_url(normalized),
         registrable when is_binary(registrable) and registrable != "" <-
           PublicSuffix.registrable_domain(host) do
      resolution = RedirectResolver.resolve(normalized, resolve_opts())
      {:ok, present_url(host, registrable, normalized, resolution)}
    else
      _ -> {:error, :invalid_url}
    end
  end

  def lookup_url(_), do: {:error, :invalid_url}

  defp present_domain(host, registrable, matches) do
    base_result(host, registrable, nil, matches)
    |> Map.merge(%{
      final_url: nil,
      final_domain: nil,
      redirect_count: 0,
      resolution_status: nil
    })
  end

  defp present_url(host, registrable, url, resolution) do
    base_result(host, registrable, url, resolution.matches)
    |> Map.merge(%{
      final_url: resolution.final_url,
      final_domain: resolution.final_hostname,
      redirect_count: resolution.redirect_count,
      resolution_status: resolution.status
    })
  end

  defp base_result(host, registrable, url, matches) do
    categories = load_categories(matches)
    blocking? = Enum.any?(categories, & &1.blocks_serving)
    slugs = Enum.map(categories, & &1.slug)
    matched? = matches != []

    %{
      domain: host,
      registrable_domain: registrable,
      url: url,
      blacklisted: matched? and blocking?,
      status: if(matched?, do: "matched", else: "clean"),
      categories: slugs,
      scanned_at: DateTime.utc_now() |> DateTime.truncate(:second),
      policy_generation: Cache.generation()
    }
  end

  defp load_categories([]), do: []

  defp load_categories(matches) do
    ids =
      matches
      |> Enum.map(& &1.category_id)
      |> Enum.uniq()

    from(c in Category,
      where: c.id in ^ids,
      where: c.enabled == true,
      order_by: c.slug
    )
    |> Repo.all()
  end

  defp resolve_opts do
    [
      allow_loopback?: Application.get_env(:nostr_spam_fighter, :allow_loopback_redirects, false),
      max_redirects: Application.get_env(:nostr_spam_fighter, :max_redirects, 8),
      url_timeout_ms: Application.get_env(:nostr_spam_fighter, :url_timeout_ms, 20_000),
      connect_timeout_ms: Application.get_env(:nostr_spam_fighter, :connect_timeout_ms, 5_000),
      request_timeout_ms: Application.get_env(:nostr_spam_fighter, :request_timeout_ms, 10_000)
    ]
  end
end
