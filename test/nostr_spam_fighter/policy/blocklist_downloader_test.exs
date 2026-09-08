defmodule NostrSpamFighter.Policy.BlocklistDownloaderTest do
  use ExUnit.Case, async: false

  alias NostrSpamFighter.Policy.BlocklistDownloader

  setup do
    prev = Application.get_env(:nostr_spam_fighter, :blocklist_max_bytes)
    Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, 20)

    on_exit(fn ->
      if prev do
        Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, prev)
      else
        Application.delete_env(:nostr_spam_fighter, :blocklist_max_bytes)
      end
    end)

    {:ok, bypass: Bypass.open()}
  end

  test "rejects from Content-Length without reading the full body", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      conn =
        conn
        |> Plug.Conn.register_before_send(fn conn ->
          Plug.Conn.put_resp_header(conn, "content-length", "52428800")
        end)
        |> Plug.Conn.send_chunked(200)

      {:ok, conn} = Plug.Conn.chunk(conn, "x")
      conn
    end)

    assert {:error, message} =
             BlocklistDownloader.get("http://127.0.0.1:#{bypass.port}/list.txt")

    assert message == "download too large (52.4 MB, limit 20 B)"
  end

  test "stops a GET without Content-Length once the limit is exceeded", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("a", 16))
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("b", 16))
      conn
    end)

    assert {:error, message} =
             BlocklistDownloader.get("http://127.0.0.1:#{bypass.port}/list.txt")

    assert message =~ "download too large"
  end

  test "reports download progress while streaming", %{bypass: bypass} do
    Application.put_env(:nostr_spam_fighter, :blocklist_max_bytes, 10_000)
    parent = self()

    Bypass.expect(bypass, "GET", "/list.txt", fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-length", "24")
        |> Plug.Conn.send_chunked(200)

      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("a", 12))
      {:ok, conn} = Plug.Conn.chunk(conn, String.duplicate("b", 12))
      conn
    end)

    assert {:ok, %{body: body}} =
             BlocklistDownloader.get("http://127.0.0.1:#{bypass.port}/list.txt", [],
               on_progress: fn progress -> send(parent, {:progress, progress}) end
             )

    assert body == String.duplicate("a", 12) <> String.duplicate("b", 12)

    progresses =
      Stream.repeatedly(fn ->
        receive do
          {:progress, progress} -> progress
        after
          50 -> :done
        end
      end)
      |> Enum.take_while(&(&1 != :done))

    assert progresses != []
    assert List.last(progresses).percent == 100.0
    assert List.last(progresses).bytes == 24
    assert List.last(progresses).total == 24
  end
end
