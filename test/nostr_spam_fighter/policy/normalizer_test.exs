defmodule NostrSpamFighter.Policy.NormalizerTest do
  use ExUnit.Case, async: true
  alias NostrSpamFighter.Policy.Normalizer

  test "lowercases and strips trailing dots" do
    assert {:ok, "example.com"} = Normalizer.normalize_host("Example.COM.")
  end

  test "normalizes urls" do
    assert {:ok, "https://example.com/path"} =
             Normalizer.normalize_url("HTTPS://Example.com/path")
  end

  test "preserves non-default ports" do
    assert {:ok, "http://example.com:8080/x"} =
             Normalizer.normalize_url("http://Example.com:8080/x")
  end

  test "keeps underscores in ASCII hostnames" do
    assert {:ok, "_dmarc.example.com"} = Normalizer.normalize_host("_DMARC.Example.COM")
    assert {:ok, "ad_track.example.com"} = Normalizer.normalize_host("ad_track.example.com")
  end

  test "keeps ASCII labels that IDNA rejects for hyphen placement" do
    assert {:ok, "0------------0-------------0.example.com"} =
             Normalizer.normalize_host("0------------0-------------0.example.com")
  end

  test "does not exit on IDNA-disallowed characters" do
    assert {:ok, "exámple_host.example"} = Normalizer.normalize_host("exámple_host.example")
  end

  test "punycodes internationalized hosts" do
    assert {:ok, "xn--mnchen-3ya.example"} = Normalizer.normalize_host("münchen.example")
  end

  test "rejects non-http schemes" do
    assert {:error, :invalid_url} = Normalizer.normalize_url("javascript:alert(1)")
    assert {:error, :invalid_url} = Normalizer.normalize_url("file:///etc/passwd")
  end
end
