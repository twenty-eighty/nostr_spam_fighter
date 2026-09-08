defmodule NostrSpamFighter.Policy.Importer do
  @moduledoc """
  Parses and stores blocklist versions atomically.
  """

  import Ecto.Query
  require Logger
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{Blocklist, BlocklistEntry, BlocklistVersion, Cache, Normalizer}

  @max_bytes 70_000_000
  @max_entries 3_000_000
  @insert_chunk 2_000
  @max_decrease_ratio 0.5

  def import_manual(%Blocklist{} = blocklist, body) when is_binary(body) do
    activate_from_body(blocklist, body, %{})
  end

  def import_remote(%Blocklist{} = blocklist, %{body: body} = meta) do
    activate_from_body(blocklist, body, meta)
  end

  def parse_entries(format, body, opts \\ []) when is_binary(body) do
    on_progress = Keyword.get(opts, :on_progress)
    limit = max_entries() + 1
    lines = split_lines(body)
    total = length(lines)
    started_ms = System.monotonic_time(:millisecond)
    Process.put(:blocklist_import_progress_at, 0)

    {entries, _seen, idx} =
      Enum.reduce_while(lines, {[], MapSet.new(), 0}, fn line, {acc, seen, idx} ->
        idx = idx + 1
        report_import_progress(on_progress, "parsing", idx, total, started_ms)

        cond do
          comment_or_blank?(line) ->
            {:cont, {acc, seen, idx}}

          true ->
            case safe_parse_line(format, line) do
              nil ->
                {:cont, {acc, seen, idx}}

              entry ->
                key = {entry.rule_type, entry.normalized_value}

                if MapSet.member?(seen, key) do
                  {:cont, {acc, seen, idx}}
                else
                  seen = MapSet.put(seen, key)
                  acc = [entry | acc]

                  if MapSet.size(seen) >= limit do
                    {:halt, {acc, seen, idx}}
                  else
                    {:cont, {acc, seen, idx}}
                  end
                end
            end
        end
      end)

    if total > 0 do
      emit_import_progress(on_progress, "parsing", idx, total)
    end

    Enum.reverse(entries)
  end

  defp activate_from_body(blocklist, body, meta) do
    cond do
      byte_size(body) > max_bytes() ->
        fail_version(blocklist, too_large_reason(byte_size(body)))

      true ->
        entries = parse_entries(blocklist.format, body, on_progress: meta[:on_progress])

        cond do
          length(entries) > max_entries() ->
            fail_version(blocklist, "too many entries")

          suspicious_decrease?(blocklist, length(entries)) ->
            fail_version(blocklist, "suspicious entry count decrease")

          entries == [] ->
            fail_version(blocklist, "no valid entries")

          true ->
            store_and_activate(blocklist, entries, meta, body)
        end
    end
  end

  defp store_and_activate(blocklist, entries, meta, body) do
    checksum = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(
      fn ->
        {:ok, version} =
          %BlocklistVersion{}
          |> BlocklistVersion.changeset(%{
            blocklist_id: blocklist.id,
            status: "validated",
            checksum: checksum,
            entry_count: length(entries),
            fetched_at: now,
            validated_at: now
          })
          |> Repo.insert()

        entry_rows =
          Enum.map(entries, fn entry ->
            %{
              id: Ecto.UUID.generate(),
              blocklist_version_id: version.id,
              rule_type: entry.rule_type,
              normalized_value: entry.normalized_value,
              inserted_at: now,
              updated_at: now
            }
          end)

        insert_entries(entry_rows, meta[:on_progress])

        {:ok, version} =
          version
          |> BlocklistVersion.changeset(%{status: "active", activated_at: now})
          |> Repo.update()

        deactivate_previous(blocklist, version.id)

        {:ok, _blocklist} =
          blocklist
          |> Blocklist.changeset(%{
            active_version_id: version.id,
            last_success_at: now,
            last_attempt_at: now,
            next_refresh_at: DateTime.add(now, blocklist.refresh_interval_s, :second),
            etag: meta[:etag],
            last_modified: meta[:last_modified],
            last_error: nil,
            refresh_status: "ok"
          })
          |> Repo.update()

        version
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, version} ->
        Cache.rebuild()
        {:ok, version}

      {:error, reason} ->
        fail_version(blocklist, format_store_error(reason))
    end
  rescue
    exception ->
      fail_version(blocklist, Exception.message(exception))
  end

  def record_failure(%Blocklist{} = blocklist, error) when is_binary(error) do
    fail_version(blocklist, error)
  end

  def permanent_failure?(error) when is_binary(error) do
    String.starts_with?(error, "download too large") or
      error in [
        "too many entries",
        "no valid entries",
        "suspicious entry count decrease"
      ]
  end

  def permanent_failure?(_), do: false

  def too_large_reason(bytes, limit \\ max_bytes()) do
    "download too large (#{format_bytes(bytes)}, limit #{format_bytes(limit)})"
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000_000 do
    "#{format_amount(bytes / 1_000_000)} MB"
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000 do
    "#{format_amount(bytes / 1_000)} KB"
  end

  def format_bytes(bytes) when is_integer(bytes) do
    "#{bytes} B"
  end

  def format_count(count) when is_integer(count) and count >= 1_000_000 do
    "#{format_amount(count / 1_000_000)}M"
  end

  def format_count(count) when is_integer(count) and count >= 1_000 do
    "#{format_amount(count / 1_000)}K"
  end

  def format_count(count) when is_integer(count), do: Integer.to_string(count)

  def max_bytes do
    Application.get_env(:nostr_spam_fighter, :blocklist_max_bytes, @max_bytes)
  end

  def max_entries do
    Application.get_env(:nostr_spam_fighter, :blocklist_max_entries, @max_entries)
  end

  defp insert_entries(rows, on_progress) do
    total = length(rows)
    started_ms = System.monotonic_time(:millisecond)
    Process.put(:blocklist_import_progress_at, 0)

    rows
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.reduce(0, fn chunk, done ->
      Repo.insert_all(BlocklistEntry, chunk)
      done = done + length(chunk)
      report_import_progress(on_progress, "saving", done, total, started_ms)
      done
    end)

    if total > 0 do
      emit_import_progress(on_progress, "saving", total, total)
    end
  end

  defp report_import_progress(nil, _stage, _done, _total, _started_ms), do: :ok

  defp report_import_progress(on_progress, stage, done, total, _started_ms) do
    now = System.monotonic_time(:millisecond)
    last = Process.get(:blocklist_import_progress_at, 0)

    if last == 0 or now - last >= 250 do
      emit_import_progress(on_progress, stage, done, total, now)
    end
  end

  defp emit_import_progress(nil, _stage, _done, _total), do: :ok

  defp emit_import_progress(on_progress, stage, done, total) do
    emit_import_progress(on_progress, stage, done, total, System.monotonic_time(:millisecond))
  end

  defp emit_import_progress(on_progress, stage, done, total, now) do
    Process.put(:blocklist_import_progress_at, now)

    on_progress.(%{
      phase: "import",
      stage: stage,
      done: done,
      total: total,
      percent: import_percent(done, total)
    })
  end

  defp import_percent(_done, total) when not is_integer(total) or total <= 0, do: nil
  defp import_percent(done, total), do: min(100.0, done / total * 100)

  defp split_lines(body) do
    for line <- :binary.split(body, "\n", [:global, :trim_all]),
        String.valid?(line) do
      String.trim_trailing(line, "\r")
    end
  end

  defp format_store_error(%{message: message}) when is_binary(message), do: message
  defp format_store_error(reason) when is_binary(reason), do: reason
  defp format_store_error(reason), do: inspect(reason)

  defp format_amount(value) do
    rounded = Float.round(value, 1)

    if rounded == :erlang.float(trunc(rounded)) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 1)
    end
  end

  defp fail_version(blocklist, error) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Logger.warning(
      "blocklist import failed name=#{inspect(blocklist.name)} url=#{blocklist.source_url} reason=#{error}"
    )

    {:ok, version} =
      %BlocklistVersion{}
      |> BlocklistVersion.changeset(%{
        blocklist_id: blocklist.id,
        status: "failed",
        error: error,
        fetched_at: now
      })
      |> Repo.insert()

    refresh_status = if(permanent_failure?(error), do: "rejected", else: "failed")

    blocklist
    |> Blocklist.changeset(%{
      last_attempt_at: now,
      last_error: error,
      refresh_status: refresh_status
    })
    |> Repo.update()

    {:error, {:import_failed, version}}
  end

  defp deactivate_previous(blocklist, new_version_id) do
    from(v in BlocklistVersion,
      where: v.blocklist_id == ^blocklist.id,
      where: v.id != ^new_version_id,
      where: v.status == "active"
    )
    |> Repo.update_all(set: [status: "superseded"])
  end

  defp suspicious_decrease?(%Blocklist{active_version_id: nil}, _count), do: false

  defp suspicious_decrease?(%Blocklist{active_version_id: version_id}, count) do
    case Repo.get(BlocklistVersion, version_id) do
      %BlocklistVersion{entry_count: previous} when previous > 0 ->
        count / previous < @max_decrease_ratio

      _ ->
        false
    end
  end

  defp comment_or_blank?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#") or String.starts_with?(trimmed, "!")
  end

  defp safe_parse_line(format, line) do
    parse_line(format, line)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp parse_line("domains", line) do
    value = first_token(line)

    case Normalizer.normalize_host(value) do
      {:ok, host} -> %{rule_type: "domain", normalized_value: host}
      _ -> nil
    end
  end

  defp parse_line("hosts", line) do
    value = hosts_file_host(line)

    case Normalizer.normalize_host(value) do
      {:ok, host} -> %{rule_type: "host", normalized_value: host}
      _ -> nil
    end
  end

  defp parse_line("urls", line) do
    value = first_token(line)

    case Normalizer.normalize_url(value) do
      {:ok, url} -> %{rule_type: "url_prefix", normalized_value: url}
      _ -> nil
    end
  end

  defp parse_line(_, _), do: nil

  defp first_token(line) do
    line
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> hd()
  end

  defp hosts_file_host(line) do
    parts = line |> String.trim() |> String.split(~r/\s+/)

    case parts do
      [maybe_ip, host | _] ->
        if ip_literal?(maybe_ip), do: host, else: maybe_ip

      [host] ->
        host
    end
  end

  defp ip_literal?(value) do
    match?({:ok, _}, :inet.parse_address(String.to_charlist(value)))
  end
end
