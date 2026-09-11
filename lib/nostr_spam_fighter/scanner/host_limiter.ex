defmodule NostrSpamFighter.Scanner.HostLimiter do
  @moduledoc false

  @table :nsf_http_host_limiter

  def setup do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        :ok
    end

    :ok
  end

  def with_host(host, fun) when is_function(fun, 0) do
    host = host || "_"
    limit = max(Application.get_env(:nostr_spam_fighter, :per_host_concurrency, 2), 1)
    checkout(host, limit)

    try do
      fun.()
    after
      checkin(host)
    end
  end

  defp checkout(host, limit) do
    setup()

    case bump(host, 1) do
      n when n <= limit ->
        :ok

      _ ->
        bump(host, -1)
        Process.sleep(20)
        checkout(host, limit)
    end
  end

  defp checkin(host), do: bump(host, -1)

  defp bump(host, delta) do
    :ets.update_counter(@table, host, {2, delta}, {host, 0})
  end
end
