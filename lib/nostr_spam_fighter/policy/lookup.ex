defmodule NostrSpamFighter.Policy.Lookup do
  @moduledoc """
  Explains which enabled blocklists currently match a host.

  Unlike the policy cache, this keeps **every** matching list — including
  multiple lists in the same category — so operators can see why a domain
  would be blocked.
  """

  import Ecto.Query

  alias NostrSpamFighter.Repo

  alias NostrSpamFighter.Policy.{
    BlocklistEntry,
    Normalizer,
    PublicSuffix
  }

  @type list_hit :: %{
          id: Ecto.UUID.t(),
          name: String.t(),
          category_id: Ecto.UUID.t(),
          category_slug: String.t(),
          category_name: String.t(),
          blocks_serving: boolean()
        }

  @type host_result :: %{
          host: String.t(),
          registrable_domain: String.t(),
          lists: [list_hit()]
        }

  @spec lists_for_host(String.t()) :: {:ok, host_result()} | {:error, :invalid_domain}
  def lists_for_host(host) when is_binary(host) do
    with {:ok, normalized} <- Normalizer.normalize_host(host),
         registrable when is_binary(registrable) and registrable != "" <-
           PublicSuffix.registrable_domain(normalized) do
      {:ok,
       %{
         host: normalized,
         registrable_domain: registrable,
         lists: lists_for_registrable(registrable)
       }}
    else
      _ -> {:error, :invalid_domain}
    end
  end

  def lists_for_host(_), do: {:error, :invalid_domain}

  @spec lists_for_registrable(String.t()) :: [list_hit()]
  def lists_for_registrable(domain) when is_binary(domain) and domain != "" do
    from(e in BlocklistEntry,
      join: v in assoc(e, :blocklist_version),
      join: b in assoc(v, :blocklist),
      join: c in assoc(b, :category),
      where: c.enabled == true,
      where: b.enabled == true,
      where: b.active_version_id == v.id,
      where: e.rule_type in ^["host", "domain"],
      where:
        e.registrable_domain == ^domain or
          (is_nil(e.registrable_domain) and e.normalized_value == ^domain),
      select: %{
        id: b.id,
        name: b.name,
        category_id: c.id,
        category_slug: c.slug,
        category_name: c.name,
        blocks_serving: c.blocks_serving
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.category_slug, &1.name})
  end

  def lists_for_registrable(_), do: []
end
