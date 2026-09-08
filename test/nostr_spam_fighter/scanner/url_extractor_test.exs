defmodule NostrSpamFighter.Scanner.UrlExtractorTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Scanner.UrlExtractor

  test "extracts image tags, markdown, autolinks, html, and bare urls" do
    event = %{
      "tags" => [["image", "https://cdn.example.com/a.png"]],
      "content" => """
      ![x](https://img.example.com/b.png)
      [link](https://news.example.com/p)
      <https://auto.example.com/z>
      <img src="https://html.example.com/c.jpg">
      See https://bare.example.com/q
      """
    }

    urls = UrlExtractor.extract(event) |> Enum.map(& &1.normalized_url) |> Enum.uniq()
    assert "https://cdn.example.com/a.png" in urls
    assert "https://img.example.com/b.png" in urls
    assert "https://news.example.com/p" in urls
    assert "https://auto.example.com/z" in urls
    assert "https://html.example.com/c.jpg" in urls
    assert "https://bare.example.com/q" in urls
  end
end
