defmodule NostrSpamFighter.Policy.BlocklistDownloader do
  @moduledoc """
  Downloads remote blocklist files with redirects, explicit timeouts,
  and an early size check so oversized files are not fully fetched.
  """

  alias NostrSpamFighter.Policy.Importer

  def get(url, extra_headers \\ [], opts \\ []) do
    connect_ms = Application.get_env(:nostr_spam_fighter, :blocklist_connect_timeout_ms, 15_000)
    receive_ms = Application.get_env(:nostr_spam_fighter, :blocklist_receive_timeout_ms, 120_000)
    max_bytes = Importer.max_bytes()
    on_progress = Keyword.get(opts, :on_progress)
    started_ms = System.monotonic_time(:millisecond)

    headers =
      [
        {"user-agent", "NostrSpamFighter/0.1 (+https://pareto.space)"},
        {"accept", "text/plain, text/*, */*"}
      ] ++ extra_headers

    opts = [
      headers: headers,
      decode_body: false,
      redirect: true,
      max_redirects: 8,
      retry: false,
      receive_timeout: receive_ms,
      connect_options: [timeout: connect_ms],
      into: stream_into(max_bytes, on_progress, started_ms)
    ]

    case Req.get(url, opts) do
      {:ok, %Req.Response{status: 304}} ->
        {:ok, :not_modified}

      {:ok, %Req.Response{status: status, body: {:too_large, size}}} when status in 200..299 ->
        {:error, Importer.too_large_reason(size, max_bytes)}

      {:ok, %Req.Response{status: status, body: body} = response} when status in 200..299 ->
        binary = IO.iodata_to_binary(body)

        if byte_size(binary) > max_bytes do
          {:error, Importer.too_large_reason(byte_size(binary), max_bytes)}
        else
          report_complete(on_progress, byte_size(binary), started_ms)

          {:ok,
           %{
             status: status,
             body: binary,
             etag: response_header(response, "etag"),
             last_modified: response_header(response, "last-modified")
           }}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status} #{status_name(status)}"}

      {:error, exception} ->
        {:error, format_exception(exception, connect_ms, receive_ms)}
    end
  end

  def format_exception(exception, connect_ms \\ 15_000, receive_ms \\ 120_000)

  def format_exception(%{reason: :timeout}, _connect_ms, receive_ms) do
    "timed out after #{div(receive_ms, 1000)}s waiting for the server"
  end

  def format_exception(%{reason: :nxdomain}, _, _) do
    "DNS lookup failed"
  end

  def format_exception(%{reason: :econnrefused}, _, _) do
    "connection refused"
  end

  def format_exception(%{reason: :closed}, _, _) do
    "connection closed before the download finished"
  end

  def format_exception(%{reason: reason}, _, _) when is_atom(reason) do
    "transport error: #{reason}"
  end

  def format_exception(exception, _, _) do
    if is_exception(exception) do
      Exception.message(exception)
    else
      inspect(exception)
    end
  end

  defp stream_into(max_bytes, on_progress, started_ms) do
    Process.put(:blocklist_progress_at, 0)

    fn {:data, data}, {req, resp} ->
      cond do
        match?({:too_large, _}, resp.body) ->
          {:halt, {req, resp}}

        declared_too_large?(resp, max_bytes) ->
          {:halt, {req, %{resp | body: {:too_large, content_length!(resp)}}}}

        true ->
          next = append_body(resp.body, data)
          size = IO.iodata_length(next)

          if size > max_bytes do
            {:halt, {req, %{resp | body: {:too_large, size}}}}
          else
            report_progress(on_progress, size, content_length(resp), started_ms)
            {:cont, {req, %{resp | body: next}}}
          end
      end
    end
  end

  defp report_progress(nil, _bytes, _total, _started_ms), do: :ok

  defp report_progress(on_progress, bytes, total, started_ms) do
    now = System.monotonic_time(:millisecond)
    last = Process.get(:blocklist_progress_at, 0)

    if last == 0 or now - last >= 250 do
      emit_progress(on_progress, bytes, total, started_ms, now)
    end
  end

  defp report_complete(nil, _bytes, _started_ms), do: :ok

  defp report_complete(on_progress, bytes, started_ms) do
    emit_progress(
      on_progress,
      bytes,
      bytes,
      started_ms,
      System.monotonic_time(:millisecond)
    )
  end

  defp emit_progress(on_progress, bytes, total, started_ms, now) do
    Process.put(:blocklist_progress_at, now)
    elapsed = max(now - started_ms, 1)

    on_progress.(%{
      bytes: bytes,
      total: total,
      percent: progress_percent(bytes, total),
      bytes_per_sec: bytes * 1000 / elapsed
    })
  end

  defp progress_percent(_bytes, total) when not is_integer(total) or total <= 0, do: nil
  defp progress_percent(bytes, total), do: min(100.0, bytes / total * 100)

  defp declared_too_large?(response, max_bytes) do
    case content_length(response) do
      size when is_integer(size) and size > max_bytes -> true
      _ -> false
    end
  end

  defp content_length!(response), do: content_length(response) || 0

  defp content_length(response) do
    case response_header(response, "content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {size, ""} -> size
          _ -> nil
        end
    end
  end

  defp append_body(body, data) when is_binary(body) or is_list(body), do: [body, data]
  defp append_body(_body, data), do: data

  defp response_header(response, name) do
    case Req.Response.get_header(response, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp status_name(301), do: "Moved Permanently"
  defp status_name(302), do: "Found"
  defp status_name(403), do: "Forbidden"
  defp status_name(404), do: "Not Found"
  defp status_name(429), do: "Too Many Requests"
  defp status_name(500), do: "Internal Server Error"
  defp status_name(502), do: "Bad Gateway"
  defp status_name(503), do: "Service Unavailable"
  defp status_name(_), do: ""
end
