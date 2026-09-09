defmodule NostrSpamFighter.Scanner.HTTPClient do
  @moduledoc """
  Controlled streaming request that connects only to a validated IP.

  Redirect following only needs status and `Location`, so this prefers HEAD
  and closes as soon as headers arrive. A GET of a large body on a 512 MB
  host can OOM before the process ever looks at the bytes.
  """

  alias NostrSpamFighter.Memory

  @redirect_statuses [301, 302, 303, 307, 308]
  @head_unsupported [405, 501]

  @spec request(map(), keyword()) ::
          {:ok, %{status: integer(), location: String.t() | nil, duration_ms: non_neg_integer()}}
          | {:error, atom()}
  def request(destination, opts \\ []) do
    if Memory.tight?() do
      :telemetry.execute([:nostr_spam_fighter, :memory, :shed], %{count: 1}, %{reason: :http})
      {:error, :memory_pressure}
    else
      started = System.monotonic_time(:millisecond)

      case fetch(destination, opts, "HEAD") do
        {:ok, %{status: status}} when status in @head_unsupported ->
          wrap_duration(fetch(destination, opts, "GET"), started)

        other ->
          wrap_duration(other, started)
      end
    end
  catch
    :exit, _ -> {:error, :connection_failure}
  end

  def redirect_status?(status), do: status in @redirect_statuses

  defp wrap_duration({:ok, result}, started) do
    {:ok, Map.put(result, :duration_ms, System.monotonic_time(:millisecond) - started)}
  end

  defp wrap_duration(other, _started), do: other

  defp fetch(destination, opts, method) do
    timeout = Keyword.get(opts, :request_timeout_ms, cfg(:request_timeout_ms, 10_000))
    connect_timeout = Keyword.get(opts, :connect_timeout_ms, cfg(:connect_timeout_ms, 5_000))
    ip = hd(destination.ips)
    ip_string = ip |> :inet.ntoa() |> List.to_string()
    scheme = if destination.scheme == "https", do: :https, else: :http
    url = Keyword.fetch!(opts, :url)

    connect_opts = [
      timeout: connect_timeout,
      hostname: destination.host,
      protocols: [:http1]
    ]

    case Mint.HTTP.connect(scheme, ip_string, destination.port, connect_opts) do
      {:ok, conn} ->
        case Mint.HTTP.request(
               conn,
               method,
               request_path(url),
               headers(destination.host, method),
               nil
             ) do
          {:ok, conn, _ref} ->
            receive_headers(conn, timeout)

          {:error, conn, _reason} ->
            Mint.HTTP.close(conn)
            {:error, :connection_failure}
        end

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Mint.TransportError{reason: :nxdomain}} ->
        {:error, :dns_failure}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_failure}

      {:error, %Mint.TransportError{reason: {:tls_alert, _}}} ->
        {:error, :tls_failure}

      {:error, %Mint.TransportError{}} ->
        {:error, :connection_failure}

      {:error, _} ->
        {:error, :connection_failure}
    end
  end

  defp headers(host, method) do
    base = [
      {"host", host},
      {"user-agent", "NostrSpamFighter/1.0"},
      {"accept", "*/*"},
      {"accept-encoding", "identity"},
      {"connection", "close"}
    ]

    if method == "GET" do
      [{"range", "bytes=0-0"} | base]
    else
      base
    end
  end

  defp request_path(url) do
    uri = URI.parse(url)
    path = uri.path || "/"
    if uri.query, do: path <> "?" <> uri.query, else: path
  end

  defp receive_headers(conn, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_receive(conn, deadline, nil, nil)
  end

  defp do_receive(conn, deadline, status, location) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      Mint.HTTP.close(conn)
      {:error, :timeout}
    else
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            :unknown ->
              do_receive(conn, deadline, status, location)

            {:ok, conn, responses} ->
              {status, location, done?} = reduce_responses(responses, status, location)

              if done? do
                Mint.HTTP.close(conn)
                finish(status, location)
              else
                do_receive(conn, deadline, status, location)
              end

            {:error, conn, _reason, _responses} ->
              Mint.HTTP.close(conn)
              {:error, :http_error}
          end
      after
        remaining ->
          Mint.HTTP.close(conn)
          {:error, :timeout}
      end
    end
  end

  defp finish(status, location) when is_integer(status) do
    {:ok, %{status: status, location: location}}
  end

  defp finish(_status, _location), do: {:error, :http_error}

  defp reduce_responses(responses, status, location) do
    Enum.reduce(responses, {status, location, false}, fn
      {:status, _ref, code}, {_, loc, done?} -> {code, loc, done?}
      {:headers, _ref, headers}, {st, loc, _} -> {st, location_header(headers) || loc, true}
      {:error, _ref, _reason}, acc -> acc
      _, acc -> acc
    end)
  end

  defp location_header(headers) do
    max = cfg(:max_redirect_location_bytes, 2_048)

    Enum.find_value(headers, fn
      {name, value} ->
        if String.downcase(to_string(name)) == "location" do
          value = to_string(value)
          if byte_size(value) <= max, do: value
        end

      _ ->
        nil
    end)
  end

  defp cfg(key, default), do: Application.get_env(:nostr_spam_fighter, key, default)
end
