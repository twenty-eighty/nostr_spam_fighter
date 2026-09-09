defmodule NostrSpamFighter.Policy.RegistrableDomainBackfill do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{BlocklistEntry, PublicSuffix}

  # Keep batches small so POOL_SIZE=5 instances are not starved by backfill.
  @batch 500
  @pause_ms 250
  @query_opts [timeout: :infinity]

  @doc """
  Fills `registrable_domain` for host/domain rows that still have NULL.

  Safe to call repeatedly. Does **not** `COUNT(*)` the table (that scans millions
  of rows and times out on small Postgres plans). Progress is driven only by
  `LIMIT` batches.
  """
  def run(opts \\ []) do
    batch = Keyword.get(opts, :batch, @batch)
    pause_ms = Keyword.get(opts, :pause_ms, @pause_ms)

    Logger.info("registrable_domain backfill: starting")
    updated = do_run(batch, pause_ms, 0)
    Logger.info("registrable_domain backfill: finished updated=#{updated}")
    {:ok, updated}
  rescue
    error ->
      Logger.error("registrable_domain backfill failed: #{Exception.message(error)}")
      {:error, error}
  end

  @doc """
  Cheap existence check — never counts the full table.
  """
  def pending? do
    Repo.exists?(
      from(e in BlocklistEntry,
        where: e.rule_type in ^["host", "domain"],
        where: is_nil(e.registrable_domain),
        limit: 1
      ),
      @query_opts
    )
  end

  defp do_run(batch, pause_ms, updated) do
    rows =
      from(e in BlocklistEntry,
        where: e.rule_type in ^["host", "domain"],
        where: is_nil(e.registrable_domain),
        select: %{id: e.id, normalized_value: e.normalized_value},
        limit: ^batch
      )
      |> Repo.all(@query_opts)

    case rows do
      [] ->
        updated

      rows ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        grouped =
          Enum.group_by(rows, fn row ->
            PublicSuffix.registrable_domain(row.normalized_value) || row.normalized_value
          end)

        Enum.each(grouped, fn {domain, group} ->
          ids = Enum.map(group, & &1.id)

          from(e in BlocklistEntry, where: e.id in ^ids)
          |> Repo.update_all([set: [registrable_domain: domain, updated_at: now]], @query_opts)
        end)

        count = updated + length(rows)

        if rem(count, batch * 20) < batch do
          Logger.info("registrable_domain backfill: progress updated=#{count}")
        end

        Process.sleep(pause_ms)
        do_run(batch, pause_ms, count)
    end
  end
end
