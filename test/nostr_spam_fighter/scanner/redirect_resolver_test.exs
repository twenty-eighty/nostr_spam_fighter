defmodule NostrSpamFighter.Scanner.RedirectResolverTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Scanner.RedirectResolver

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base: "http://127.0.0.1:#{bypass.port}"}
  end

  test "follows 302 relative location", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "HEAD", "/from", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/to")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "HEAD", "/to", fn conn ->
      Plug.Conn.resp(conn, 200, "ok")
    end)

    result = RedirectResolver.resolve(base <> "/from", allow_loopback?: true)
    assert result.status == "completed"
    assert result.redirect_count == 1
    assert length(result.hops) == 2
  end

  test "detects redirect loops", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "HEAD", "/loop", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/loop")
      |> Plug.Conn.resp(302, "")
    end)

    result = RedirectResolver.resolve(base <> "/loop", allow_loopback?: true)
    assert result.status == "redirect_loop"
  end

  test "caps redirect hops", %{bypass: bypass, base: base} do
    for i <- 0..2 do
      Bypass.expect(bypass, "HEAD", "/r#{i}", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "/r#{i + 1}")
        |> Plug.Conn.resp(301, "")
      end)
    end

    result = RedirectResolver.resolve(base <> "/r0", allow_loopback?: true, max_redirects: 2)
    assert result.status == "too_many_redirects"
  end

  test "malformed redirect without location", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "HEAD", "/bad", fn conn ->
      Plug.Conn.resp(conn, 302, "")
    end)

    result = RedirectResolver.resolve(base <> "/bad", allow_loopback?: true)
    assert result.status == "malformed_redirect"
  end

  test "follows HEAD redirects onto a media URL without issuing GET", %{
    bypass: bypass,
    base: base
  } do
    Bypass.expect(bypass, "HEAD", "/from", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/s2048x3072/photo.png")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "HEAD", "/s2048x3072/photo.png", fn conn ->
      Plug.Conn.resp(conn, 200, String.duplicate("x", 50_000))
    end)

    result = RedirectResolver.resolve(base <> "/from", allow_loopback?: true)
    assert result.status == "completed"
    assert result.redirect_count == 1
    assert result.final_url =~ "/s2048x3072/photo.png"
  end

  test "blocked original host without allow_loopback", %{base: base} do
    result = RedirectResolver.resolve(base <> "/x", allow_loopback?: false)
    assert result.status == "blocked_address"
  end

  test "skips HTTP under memory pressure", %{base: base} do
    prev_pressure = Application.get_env(:nostr_spam_fighter, :memory_pressure, :unset)
    prev_fun = Application.get_env(:nostr_spam_fighter, :memory_usage_fun, :unset)
    prev_limit = Application.get_env(:nostr_spam_fighter, :memory_limit_bytes, :unset)

    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 100 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 10)

    on_exit(fn ->
      restore_env(:memory_pressure, prev_pressure)
      restore_env(:memory_usage_fun, prev_fun)
      restore_env(:memory_limit_bytes, prev_limit)
    end)

    result = RedirectResolver.resolve(base <> "/x", allow_loopback?: true)
    assert result.status == "memory_pressure"
  end

  defp restore_env(key, :unset), do: Application.delete_env(:nostr_spam_fighter, key)
  defp restore_env(key, value), do: Application.put_env(:nostr_spam_fighter, key, value)
end
