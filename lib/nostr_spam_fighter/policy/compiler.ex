defmodule NostrSpamFighter.Policy.Compiler do
  @moduledoc false

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{BlocklistEntry, Cache}

  def compile do
    rules =
      from(e in BlocklistEntry,
        join: v in assoc(e, :blocklist_version),
        join: b in assoc(v, :blocklist),
        join: c in assoc(b, :category),
        where: c.enabled == true,
        where: b.enabled == true,
        where: b.active_version_id == v.id,
        select: %{
          entry_id: e.id,
          rule_type: e.rule_type,
          normalized_value: e.normalized_value,
          blocklist_id: b.id,
          blocklist_version_id: v.id,
          category_id: c.id,
          category_slug: c.slug,
          blocks_serving: c.blocks_serving
        }
      )
      |> Repo.all()

    generation = bump_generation()
    Cache.put_compiled(generation, rules)
    {:ok, generation}
  rescue
    error -> {:error, error}
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
end
