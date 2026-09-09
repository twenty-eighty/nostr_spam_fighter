defmodule NostrSpamFighter.Policy.RegistrableDomainBackfill do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{BlocklistEntry, PublicSuffix}

  @batch 2_000

  @doc """
  Fills `registrable_domain` for host/domain rows that still have NULL.

  Safe to call repeatedly. Runs in small batches so it can finish after boot
  without blocking migrate or starving the web process.
  """
  def run(opts \\ []) do
    batch = Keyword.get(opts, :batch, @batch)
    total = pending_count()

    if total == 0 do
      Logger.info("registrable_domain backfill: nothing to do")
      {:ok, 0}
    else
      Logger.info("registrable_domain backfill: starting rows=#{total}")
      updated = do_run(batch, 0)
      Logger.info("registrable_domain backfill: finished updated=#{updated}")
      {:ok, updated}
    end
  end

  def pending_count do
    Repo.one(
      from(e in BlocklistEntry,
        where: e.rule_type in ^["host", "domain"],
        where: is_nil(e.registrable_domain),
        select: count(e.id)
      )
    ) || 0
  end

  defp do_run(batch, updated) do
    rows =
      from(e in BlocklistEntry,
        where: e.rule_type in ^["host", "domain"],
        where: is_nil(e.registrable_domain),
        select: %{id: e.id, normalized_value: e.normalized_value},
        limit: ^batch
      )
      |> Repo.all()

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
          |> Repo.update_all(set: [registrable_domain: domain, updated_at: now])
        end)

        count = updated + length(rows)

        if rem(count, batch * 10) < batch do
          Logger.info("registrable_domain backfill: progress updated=#{count}")
        end

        # Yield so the web endpoint stays responsive on small instances.
        Process.sleep(50)
        do_run(batch, count)
    end
  end
end
