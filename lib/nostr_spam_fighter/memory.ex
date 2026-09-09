defmodule NostrSpamFighter.Memory do
  @moduledoc """
  Best-effort cgroup/BEAM memory reading so we can shed work before OOM.

  On Render and other cgroup hosts this uses `memory.current` / `memory.max`.
  Tests inject `:memory_usage_fun` and `:memory_limit_bytes`.
  """

  @cgroup_usage [
    "/sys/fs/cgroup/memory.current",
    "/sys/fs/cgroup/memory/memory.usage_in_bytes"
  ]

  @cgroup_limit [
    "/sys/fs/cgroup/memory.max",
    "/sys/fs/cgroup/memory/memory.limit_in_bytes"
  ]

  @spec tight?() :: boolean()
  def tight? do
    if Application.get_env(:nostr_spam_fighter, :memory_pressure, true) do
      usage = usage_bytes()
      limit = limit_bytes()
      tight?(usage, limit)
    else
      false
    end
  end

  @spec snapshot() :: %{
          usage_bytes: non_neg_integer() | nil,
          limit_bytes: pos_integer() | nil,
          tight?: boolean()
        }
  def snapshot do
    usage = usage_bytes()
    limit = limit_bytes()

    %{
      usage_bytes: usage,
      limit_bytes: limit,
      tight?:
        Application.get_env(:nostr_spam_fighter, :memory_pressure, true) and
          tight?(usage, limit)
    }
  end

  defp tight?(usage, limit) when is_integer(usage) and is_integer(limit) and limit > 0 do
    usage >= trunc(limit * ratio())
  end

  defp tight?(_, _), do: false

  defp usage_bytes do
    case Application.get_env(:nostr_spam_fighter, :memory_usage_fun) do
      fun when is_function(fun, 0) -> fun.()
      _ -> read_cgroup_int(@cgroup_usage) || :erlang.memory(:total)
    end
  end

  defp limit_bytes do
    Application.get_env(:nostr_spam_fighter, :memory_limit_bytes) ||
      read_cgroup_int(@cgroup_limit)
  end

  defp ratio do
    Application.get_env(:nostr_spam_fighter, :memory_pressure_ratio, 0.75)
  end

  defp read_cgroup_int(paths) do
    Enum.find_value(paths, &parse_cgroup_int/1)
  end

  defp parse_cgroup_int(path) do
    case File.read(path) do
      {:ok, contents} -> parse_limit(String.trim(contents))
      _ -> nil
    end
  end

  defp parse_limit("max"), do: nil

  defp parse_limit(text) do
    case Integer.parse(text) do
      {n, _} when n > 0 and n < 1_099_511_627_776 -> n
      {_n, _} -> nil
      :error -> nil
    end
  end
end
