defmodule NostrSpamFighter.Scanner.HTTPClient do
  @moduledoc """
  Controlled streaming GET that connects only to a validated IP.
  """

  @redirect_statuses [301, 302, 303, 307, 308]

  @spec request(map(), keyword()) ::
          {:ok, %{status: integer(), location: String.t() | nil, duration_ms: non_neg_integer()}}
          | {:error, atom()}
  def request(destination, opts \\ []) do
    started = System.monotonic_time(:millisecond)
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

    with {:ok, conn} <- Mint.HTTP.connect(scheme, ip_string, destination.port, connect_opts),
         {:ok, conn, _ref} <-
           Mint.HTTP.request(conn, "GET", request_path(url), headers(destination.host), nil) do
      result = receive_headers(conn, timeout)
      duration = System.monotonic_time(:millisecond) - started

      case result do
        {:ok, status, location} ->
          {:ok, %{status: status, location: location, duration_ms: duration}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, %Mint.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, %Mint.TransportError{reason: :nxdomain}} -> {:error, :dns_failure}
      {:error, %Mint.TransportError{reason: :econnrefused}} -> {:error, :connection_failure}
      {:error, %Mint.TransportError{reason: {:tls_alert, _}}} -> {:error, :tls_failure}
      {:error, %Mint.TransportError{}} -> {:error, :connection_failure}
      {:error, _} -> {:error, :connection_failure}
    end
  catch
    :exit, _ -> {:error, :connection_failure}
  end

  def redirect_status?(status), do: status in @redirect_statuses

  defp headers(host) do
    [
      {"host", host},
      {"user-agent", "NostrSpamFighter/1.0"},
      {"accept", "*/*"}
    ]
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
                {:ok, status, location}
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

  defp reduce_responses(responses, status, location) do
    Enum.reduce(responses, {status, location, false}, fn
      {:status, _ref, code}, {_, loc, done?} -> {code, loc, done?}
      {:headers, _ref, headers}, {st, loc, _} -> {st, location_header(headers) || loc, true}
      {:error, _ref, _reason}, acc -> acc
      _, acc -> acc
    end)
  end

  defp location_header(headers) do
    Enum.find_value(headers, fn
      {name, value} ->
        if String.downcase(to_string(name)) == "location", do: to_string(value)

      _ ->
        nil
    end)
  end

  defp cfg(key, default), do: Application.get_env(:nostr_spam_fighter, key, default)
end
