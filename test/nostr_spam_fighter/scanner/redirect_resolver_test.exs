defmodule NostrSpamFighter.Scanner.RedirectResolverTest do
  use NostrSpamFighter.DataCase, async: false

  alias NostrSpamFighter.Scanner.RedirectResolver

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base: "http://127.0.0.1:#{bypass.port}"}
  end

  test "follows 302 relative location", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "GET", "/from", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/to")
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "GET", "/to", fn conn ->
      Plug.Conn.resp(conn, 200, "ok")
    end)

    result = RedirectResolver.resolve(base <> "/from", allow_loopback?: true)
    assert result.status == "completed"
    assert result.redirect_count == 1
    assert length(result.hops) == 2
  end

  test "detects redirect loops", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "GET", "/loop", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "/loop")
      |> Plug.Conn.resp(302, "")
    end)

    result = RedirectResolver.resolve(base <> "/loop", allow_loopback?: true)
    assert result.status == "redirect_loop"
  end

  test "caps redirect hops", %{bypass: bypass, base: base} do
    for i <- 0..2 do
      Bypass.expect(bypass, "GET", "/r#{i}", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "/r#{i + 1}")
        |> Plug.Conn.resp(301, "")
      end)
    end

    result = RedirectResolver.resolve(base <> "/r0", allow_loopback?: true, max_redirects: 2)
    assert result.status == "too_many_redirects"
  end

  test "malformed redirect without location", %{bypass: bypass, base: base} do
    Bypass.expect(bypass, "GET", "/bad", fn conn ->
      Plug.Conn.resp(conn, 302, "")
    end)

    result = RedirectResolver.resolve(base <> "/bad", allow_loopback?: true)
    assert result.status == "malformed_redirect"
  end

  test "blocked original host without allow_loopback", %{base: base} do
    result = RedirectResolver.resolve(base <> "/x", allow_loopback?: false)
    assert result.status == "blocked_address"
  end
end
