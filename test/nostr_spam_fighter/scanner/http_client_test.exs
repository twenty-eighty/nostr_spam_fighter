defmodule NostrSpamFighter.Scanner.HTTPClientTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Scanner.{AddressValidator, HTTPClient}

  setup do
    bypass = Bypass.open()
    url = "http://127.0.0.1:#{bypass.port}/page"
    {:ok, dest} = AddressValidator.validate_url(url, allow_loopback?: true)
    {:ok, bypass: bypass, dest: dest, url: url}
  end

  test "prefers HEAD and does not need the response body", %{
    bypass: bypass,
    dest: dest,
    url: url
  } do
    Bypass.expect(bypass, fn conn ->
      assert conn.method == "HEAD"

      conn
      |> Plug.Conn.put_resp_header("location", "/next")
      |> Plug.Conn.resp(302, "")
    end)

    assert {:ok, %{status: 302, location: "/next"}} =
             HTTPClient.request(dest, url: url, allow_loopback?: true)
  end

  test "does not fall back to GET when HEAD is not allowed", %{
    bypass: bypass,
    dest: dest,
    url: url
  } do
    Bypass.expect(bypass, "HEAD", "/page", fn conn ->
      Plug.Conn.resp(conn, 405, "")
    end)

    assert {:ok, %{status: 405, location: nil}} = HTTPClient.request(dest, url: url)
  end

  test "drops oversized Location headers", %{bypass: bypass, dest: dest, url: url} do
    Bypass.expect(bypass, "HEAD", "/page", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", String.duplicate("a", 3_000))
      |> Plug.Conn.resp(302, "")
    end)

    assert {:ok, %{status: 302, location: nil}} = HTTPClient.request(dest, url: url)
  end

  test "refuses to connect under memory pressure", %{dest: dest, url: url} do
    prev_pressure = Application.get_env(:nostr_spam_fighter, :memory_pressure, :unset)
    prev_fun = Application.get_env(:nostr_spam_fighter, :memory_usage_fun, :unset)
    prev_limit = Application.get_env(:nostr_spam_fighter, :memory_limit_bytes, :unset)

    Application.put_env(:nostr_spam_fighter, :memory_pressure, true)
    Application.put_env(:nostr_spam_fighter, :memory_usage_fun, fn -> 100 end)
    Application.put_env(:nostr_spam_fighter, :memory_limit_bytes, 10)

    on_exit(fn ->
      restore(:memory_pressure, prev_pressure)
      restore(:memory_usage_fun, prev_fun)
      restore(:memory_limit_bytes, prev_limit)
    end)

    assert {:error, :memory_pressure} = HTTPClient.request(dest, url: url)
  end

  defp restore(key, :unset), do: Application.delete_env(:nostr_spam_fighter, key)
  defp restore(key, value), do: Application.put_env(:nostr_spam_fighter, key, value)
end
