defmodule NostrSpamFighter.Scanner.RedirectResolver do
  @moduledoc """
  Follows redirects safely, matching policy on every hop.
  """

  alias NostrSpamFighter.Policy.{Matcher, Normalizer}
  alias NostrSpamFighter.Scanner.{AddressValidator, HTTPClient}

  @redirect_statuses [301, 302, 303, 307, 308]

  @spec resolve(String.t(), keyword()) :: map()
  def resolve(url, opts \\ []) do
    started = System.monotonic_time(:millisecond)
    max_redirects = Keyword.get(opts, :max_redirects, cfg(:max_redirects, 8))
    overall = Keyword.get(opts, :url_timeout_ms, cfg(:url_timeout_ms, 20_000))
    deadline = System.monotonic_time(:millisecond) + overall

    follow(url, opts, deadline, max_redirects, MapSet.new(), [])
    |> Map.put(:duration_ms, System.monotonic_time(:millisecond) - started)
  end

  defp follow(url, opts, deadline, left, seen, hops) do
    cond do
      System.monotonic_time(:millisecond) > deadline ->
        finish(:timeout, hops, url)

      true ->
        case Normalizer.normalize_url(url) do
          {:error, _} ->
            finish(:invalid_url, hops, url)

          {:ok, normalized} ->
            if MapSet.member?(seen, normalized) do
              finish(:redirect_loop, hops, normalized)
            else
              do_hop(normalized, opts, deadline, left, MapSet.put(seen, normalized), hops)
            end
        end
    end
  end

  defp do_hop(url, opts, deadline, left, seen, hops) do
    allow_loopback? = Keyword.get(opts, :allow_loopback?, false)
    matches = Matcher.match_target(url, Normalizer.hostname_from_url(url))
    fetch_hop(url, opts, deadline, left, seen, hops, matches, allow_loopback?)
  end

  defp fetch_hop(url, opts, deadline, left, seen, hops, matches, allow_loopback?) do
    case AddressValidator.validate_url(url, allow_loopback?: allow_loopback?) do
      {:error, reason} ->
        hop = hop_record(length(hops), url, nil, nil, nil, matches)
        finish(reason, hops ++ [hop], url)

      {:ok, dest} ->
        case HTTPClient.request(dest, Keyword.put(opts, :url, url)) do
          {:ok, %{status: status, location: location, duration_ms: duration}} ->
            hop =
              hop_record(length(hops), url, dest, status, location, matches)
              |> Map.put(:duration_ms, duration)

            hops = hops ++ [hop]

            cond do
              status in @redirect_statuses and left <= 0 ->
                finish(:too_many_redirects, hops, url)

              status in @redirect_statuses ->
                case resolve_location(url, location) do
                  {:ok, next} -> follow(next, opts, deadline, left - 1, seen, hops)
                  {:error, reason} -> finish(reason, hops, url)
                end

              true ->
                finish(:completed, hops, url)
            end

          {:error, reason} ->
            hop = hop_record(length(hops), url, dest, nil, nil, matches)
            finish(reason, hops ++ [hop], url)
        end
    end
  end

  defp finish(status, hops, final_url) do
    last = List.last(hops)

    %{
      status: to_string(status),
      hops: hops,
      matches: Enum.flat_map(hops, & &1.matches),
      final_url: final_url,
      final_hostname: last && last.hostname,
      http_status: last && last.http_status,
      redirect_count: max(length(hops) - 1, 0),
      error: if(status == :completed, do: nil, else: to_string(status))
    }
  end

  defp hop_record(index, url, dest, status, location, matches) do
    %{
      hop_index: index,
      url: url,
      hostname: (dest && dest.host) || Normalizer.hostname_from_url(url),
      resolved_ip: dest && ip_to_string(hd(dest.ips)),
      http_status: status,
      location: location,
      duration_ms: nil,
      matches: matches
    }
  end

  defp resolve_location(_current, nil), do: {:error, :malformed_redirect}
  defp resolve_location(_current, ""), do: {:error, :malformed_redirect}

  defp resolve_location(current, location) do
    uri = URI.parse(location)

    cond do
      uri.scheme in ["http", "https"] ->
        Normalizer.normalize_url(location)

      uri.scheme in [nil, ""] ->
        current
        |> URI.parse()
        |> URI.merge(location)
        |> URI.to_string()
        |> Normalizer.normalize_url()

      true ->
        {:error, :unsupported_scheme}
    end
  end

  defp ip_to_string(ip), do: ip |> :inet.ntoa() |> List.to_string()
  defp cfg(key, default), do: Application.get_env(:nostr_spam_fighter, key, default)
end
