defmodule NostrSpamFighter.Scanner.SkipHostsTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Scanner.{RedirectResolver, SkipHosts, SkipRedirectHost}

  test "parse accepts a hostname or a full media URL" do
    assert {:ok, "blossom.primal.net"} = SkipRedirectHost.parse("blossom.primal.net")

    assert {:ok, "m.primal.net"} =
             SkipRedirectHost.parse("https://m.primal.net/PYun.jpg")

    assert {:error, :invalid_host} = SkipRedirectHost.parse("not a host")
  end

  test "create reloads the skip cache used by redirect following" do
    refute SkipHosts.member?("void.cat")

    assert {:ok, row} = SkipHosts.create(%{host: "https://void.cat/abc.png"})
    assert row.host == "void.cat"
    assert SkipHosts.member?("void.cat")

    result = RedirectResolver.resolve("https://void.cat/abc.png")
    assert result.status == "skipped_host"
    assert result.final_hostname == "void.cat"
  end

  test "duplicate hosts are rejected" do
    assert {:ok, _} = SkipHosts.create(%{host: "cdn.example"})
    assert {:error, changeset} = SkipHosts.create(%{host: "cdn.example"})
    assert %{host: [_ | _]} = errors_on(changeset)
  end
end
