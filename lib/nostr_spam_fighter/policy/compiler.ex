defmodule NostrSpamFighter.Policy.Compiler do
  @moduledoc false

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{BlocklistEntry, Cache}

  @stream_chunk 2_000

  def compile do
    domains = Cache.new_domains_table()

    try do
      Repo.transaction(
        fn ->
          rules_query()
          |> Repo.stream(max_rows: @stream_chunk)
          |> Stream.each(fn rule ->
            Cache.insert_rule(domains, rule)
          end)
          |> Stream.run()
        end,
        timeout: :infinity
      )
      |> case do
        {:ok, _} ->
          generation = bump_generation()
          Cache.install(generation, domains)
          {:ok, generation}

        {:error, reason} ->
          delete_table(domains)
          {:error, reason}
      end
    rescue
      error ->
        delete_table(domains)
        {:error, error}
    end
  end

  defp rules_query do
    from(e in BlocklistEntry,
      join: v in assoc(e, :blocklist_version),
      join: b in assoc(v, :blocklist),
      join: c in assoc(b, :category),
      where: c.enabled == true,
      where: b.enabled == true,
      where: b.active_version_id == v.id,
      where: e.rule_type in ^["host", "domain"],
      select: %{
        entry_id: e.id,
        rule_type: e.rule_type,
        normalized_value: e.normalized_value,
        blocklist_id: b.id,
        blocklist_version_id: v.id,
        category_id: c.id
      }
    )
  end

  defp bump_generation do
    current =
      case Repo.one(from g in "policy_generations", select: max(g.generation)) do
        nil -> 0
        max -> max
      end

    next = current + 1

    Repo.insert_all("policy_generations", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        generation: next,
        reason: "compile",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    next
  end

  defp delete_table(tid) do
    if :ets.info(tid) != :undefined, do: :ets.delete(tid)
  rescue
    ArgumentError -> :ok
  end
end
