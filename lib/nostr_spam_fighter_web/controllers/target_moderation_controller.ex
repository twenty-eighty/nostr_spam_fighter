defmodule NostrSpamFighterWeb.TargetModerationController do
  use NostrSpamFighterWeb, :controller

  require Logger

  alias NostrSpamFighter.Moderation.TargetState

  def domain(conn, %{"domain" => domain}) do
    case TargetState.lookup_domain(domain) do
      {:ok, result} ->
        log_moderation("domain", result)
        respond(conn, result)

      {:error, :invalid_domain} ->
        Logger.info("domain moderation error=invalid_domain target=#{domain}")
        conn |> put_status(:bad_request) |> json(%{error: "invalid domain"})
    end
  end

  def url(conn, params) do
    url = params["url"]

    cond do
      not is_binary(url) or String.trim(url) == "" ->
        Logger.info("url moderation error=url_required")
        conn |> put_status(:bad_request) |> json(%{error: "url required"})

      true ->
        Logger.info("url moderation start host=#{url_host(url)} target=#{truncate_url(url)}")

        case TargetState.lookup_url(url) do
          {:ok, result} ->
            log_moderation("url", result, ["target=#{truncate_url(url)}"])
            respond(conn, result)

          {:error, :url_too_long} ->
            Logger.info("url moderation error=url_too_long target=#{truncate_url(url)}")
            conn |> put_status(:bad_request) |> json(%{error: "url too long"})

          {:error, :invalid_url} ->
            Logger.info("url moderation error=invalid_url target=#{truncate_url(url)}")
            conn |> put_status(:bad_request) |> json(%{error: "invalid url"})
        end
    end
  end

  defp respond(conn, result) do
    etag = etag(result)

    if get_req_header(conn, "if-none-match") == [etag] do
      conn |> put_resp_header("etag", etag) |> send_resp(304, "")
    else
      conn |> put_resp_header("etag", etag) |> json(public(result))
    end
  end

  defp public(result) do
    result
    |> Map.take([
      :domain,
      :registrable_domain,
      :url,
      :final_url,
      :final_domain,
      :redirect_count,
      :resolution_status,
      :blacklisted,
      :status,
      :categories,
      :lists,
      :scanned_at,
      :policy_generation
    ])
    |> Map.update(:lists, [], &public_lists/1)
  end

  defp public_lists(lists) when is_list(lists) do
    Enum.map(lists, fn list ->
      Map.take(list, [:id, :name, :category_slug, :category_name, :blocks_serving])
    end)
  end

  defp public_lists(_), do: []

  defp log_moderation(kind, result, extras \\ []) do
    Logger.info(compact_moderation(kind, result, extras))
  end

  defp compact_moderation(kind, result, extras) do
    [
      "#{kind} moderation",
      verdict(result),
      "host=#{result.domain}",
      final_part(result),
      redirects_part(result),
      fetch_part(result),
      cats_part(result),
      lists_part(result)
    ]
    |> Kernel.++(extras)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp verdict(%{blacklisted: true}), do: "blocked"
  defp verdict(%{status: "matched"}), do: "listed"
  defp verdict(_), do: "clean"

  defp final_part(%{final_domain: final, domain: host})
       when is_binary(final) and final != host,
       do: "final=#{final}"

  defp final_part(_), do: nil

  defp redirects_part(%{redirect_count: n}) when is_integer(n) and n > 0, do: "redirects=#{n}"
  defp redirects_part(_), do: nil

  defp fetch_part(%{resolution_status: status}) when is_binary(status), do: "fetch=#{status}"
  defp fetch_part(_), do: nil

  defp cats_part(%{categories: cats}) when is_list(cats) and cats != [],
    do: "cats=#{Enum.join(cats, ",")}"

  defp cats_part(_), do: nil

  defp lists_part(%{lists: lists}) when is_list(lists) and lists != [] do
    names =
      lists
      |> Enum.map(&list_name/1)
      |> Enum.reject(&is_nil/1)

    "lists=#{Enum.join(names, ",")}"
  end

  defp lists_part(_), do: nil

  defp list_name(%{name: name}) when is_binary(name), do: name
  defp list_name(_), do: nil

  defp url_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> "?"
    end
  end

  defp truncate_url(url) when byte_size(url) > 200, do: binary_part(url, 0, 200) <> "…"
  defp truncate_url(url), do: url

  defp etag(result) do
    material =
      Enum.join(
        [
          result[:registrable_domain],
          result[:final_url],
          result[:policy_generation],
          result[:resolution_status],
          Enum.join(result[:categories] || [], ","),
          result[:lists] |> List.wrap() |> Enum.map(& &1[:id]) |> Enum.join(",")
        ],
        ":"
      )

    ~s("#{Base.encode16(:crypto.hash(:sha256, material), case: :lower)}")
  end
end
