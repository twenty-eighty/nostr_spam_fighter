defmodule NostrSpamFighter.Scanner.UrlExtractor do
  @moduledoc """
  Extracts HTTP/HTTPS URLs from kind 30023 events.
  """

  # Exclude markdown/JSON punctuation so bare matches do not swallow escapes like `file.webp\`.
  @url_regex ~r/https?:\/\/[^\s<>\[\]()"'\\`]+/i
  @md_image ~r/!\[[^\]]*\]\((https?:\/\/[^)\s]+)/i
  @md_link ~r/(?<!!)\[[^\]]*\]\((https?:\/\/[^)\s]+)/i
  @autolink ~r/<(https?:\/\/[^>]+)>/i
  @html_attr ~r/(?:src|href)\s*=\s*["'](https?:\/\/[^"']+)["']/i
  @trailing_junk ~r/[\\).,;:!?'"\]]+$/

  @spec extract(map()) :: [map()]
  def extract(event) when is_map(event) do
    from_tags(event["tags"] || []) ++ from_content(event["content"] || "")
  end

  defp from_tags(tags) do
    Enum.flat_map(tags, fn
      ["image", url | _] -> occurrence(url, "image_tag", "image")
      ["imeta" | rest] -> imeta_urls(rest)
      _ -> []
    end)
  end

  defp imeta_urls(rest) do
    rest
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(fn part ->
      case String.split(part, " ", parts: 2) do
        ["url", url] -> occurrence(url, "imeta_tag", "imeta")
        _ -> []
      end
    end)
  end

  defp from_content(content) do
    md_images = Regex.scan(@md_image, content) |> Enum.map(&hd(tl(&1)))
    md_links = Regex.scan(@md_link, content) |> Enum.map(&hd(tl(&1)))
    autolinks = Regex.scan(@autolink, content) |> Enum.map(&hd(tl(&1)))
    html = Regex.scan(@html_attr, content) |> Enum.map(&hd(tl(&1)))
    bare = Regex.scan(@url_regex, content) |> Enum.map(&hd/1)

    Enum.concat([
      Enum.flat_map(md_images, &occurrence(&1, "markdown_image", "content")),
      Enum.flat_map(md_links, &occurrence(&1, "markdown_link", "content")),
      Enum.flat_map(autolinks, &occurrence(&1, "autolink", "content")),
      Enum.flat_map(html, &occurrence(&1, "html_attr", "content")),
      Enum.flat_map(bare, &occurrence(&1, "bare_url", "content"))
    ])
  end

  defp occurrence(url, source_type, source_location) do
    url = clean_url(url)

    case NostrSpamFighter.Policy.Normalizer.normalize_url(url) do
      {:ok, normalized} ->
        [
          %{
            original_url: url,
            normalized_url: normalized,
            hostname: NostrSpamFighter.Policy.Normalizer.hostname_from_url(normalized),
            source_type: source_type,
            source_location: source_location
          }
        ]

      _ ->
        []
    end
  end

  defp clean_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> then(&Regex.replace(@trailing_junk, &1, ""))
  end
end
