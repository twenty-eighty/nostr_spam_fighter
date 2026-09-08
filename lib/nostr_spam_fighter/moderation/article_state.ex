defmodule NostrSpamFighter.Moderation.ArticleState do
  @moduledoc """
  Materializes current-revision moderation state for the protected API.
  """

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.Event
  alias NostrSpamFighter.Policy.Category

  alias NostrSpamFighter.Moderation.{
    ArticleAddress,
    ArticleModerationCategory,
    ArticleModerationState,
    Classification,
    OnDemand,
    Scan
  }

  def refresh_for_event(event_id) do
    case Repo.get(Event, event_id) do
      %Event{article_address: address} when is_binary(address) ->
        case Repo.get_by(ArticleAddress, address: address) do
          nil -> :ok
          article -> refresh(article)
        end

      _ ->
        :ok
    end
  end

  def refresh_all_for_policy, do: Repo.all(ArticleAddress) |> Enum.each(&refresh/1)

  def refresh(%ArticleAddress{} = article) do
    current_id = article.current_event_id
    scan = current_id && latest_scan(current_id)
    {status, blacklisted, slugs, generation} = derive(scan)

    Repo.transaction(fn ->
      state =
        case Repo.get_by(ArticleModerationState, article_address_id: article.id) do
          nil ->
            %ArticleModerationState{}
            |> ArticleModerationState.changeset(%{
              article_address_id: article.id,
              event_id: current_id,
              scan_id: scan && scan.id,
              status: status,
              blacklisted: blacklisted,
              policy_generation: generation
            })
            |> Repo.insert!()

          existing ->
            existing
            |> ArticleModerationState.changeset(%{
              event_id: current_id,
              scan_id: scan && scan.id,
              status: status,
              blacklisted: blacklisted,
              policy_generation: generation
            })
            |> Repo.update!()
        end

      Repo.delete_all(
        from c in ArticleModerationCategory, where: c.article_moderation_state_id == ^state.id
      )

      Enum.each(slugs, fn {category_id, slug} ->
        Repo.insert!(%ArticleModerationCategory{
          article_moderation_state_id: state.id,
          category_id: category_id,
          slug: slug
        })
      end)

      state
    end)
  end

  def lookup_by_naddr(naddr) do
    case decode_naddr(naddr) do
      {:ok, %{kind: kind, pubkey: pubkey, identifier: d_tag} = data} when kind == 30_023 ->
        OnDemand.ensure(data)
        address = ArticleAddress.canonical(kind, pubkey, d_tag)
        article = Repo.get_by(ArticleAddress, kind: kind, pubkey: pubkey, d_tag: d_tag)
        {:ok, present(naddr, address, article)}

      {:ok, %{kind: _kind}} ->
        {:error, :unsupported_kind}

      {:error, _} ->
        {:error, :malformed_naddr}
    end
  end

  def decode_naddr(naddr) do
    case NostrElixir.Nip19.Address.decode(naddr) do
      {:ok, :naddr, data} -> {:ok, data}
      _ -> {:error, :invalid}
    end
  end

  defp present(naddr, address, nil) do
    %{
      naddr: naddr,
      address: address,
      blacklisted: nil,
      status: "unknown",
      event_id: nil,
      event_created_at: nil,
      categories: [],
      scanned_at: nil,
      policy_generation: nil
    }
  end

  defp present(naddr, address, article) do
    state =
      ArticleModerationState
      |> Repo.get_by(article_address_id: article.id)
      |> Repo.preload([:categories, :scan])

    cond do
      is_nil(state) ->
        %{
          naddr: naddr,
          address: address,
          blacklisted: nil,
          status: pending_or_unknown(article),
          event_id: article.current_event_id,
          event_created_at: article.current_event_created_at,
          categories: [],
          scanned_at: nil,
          policy_generation: nil
        }

      true ->
        %{
          naddr: naddr,
          address: address,
          blacklisted: state.blacklisted,
          status: state.status,
          event_id: state.event_id,
          event_created_at: article.current_event_created_at,
          categories: Enum.map(state.categories, & &1.slug),
          scanned_at: state.scan && state.scan.completed_at,
          policy_generation: state.policy_generation,
          scan_id: state.scan_id
        }
    end
  end

  defp pending_or_unknown(%{current_event_id: nil}), do: "unknown"
  defp pending_or_unknown(_), do: "pending"

  defp latest_scan(event_id) do
    Repo.one(
      from s in Scan, where: s.event_id == ^event_id, order_by: [desc: s.inserted_at], limit: 1
    )
  end

  defp derive(nil), do: {"pending", nil, [], nil}

  defp derive(%Scan{status: status} = scan) do
    slugs =
      from(c in Classification,
        join: cat in Category,
        on: cat.id == c.category_id,
        where: c.scan_id == ^scan.id and c.status == "current" and cat.enabled == true,
        select: {cat.id, cat.slug, cat.blocks_serving}
      )
      |> Repo.all()

    blocking = Enum.filter(slugs, fn {_id, _slug, blocks} -> blocks end)
    blacklisted = if status in ["pending", "running"], do: nil, else: blocking != []
    api_status = api_status(status)

    {api_status, blacklisted, Enum.map(slugs, fn {id, slug, _} -> {id, slug} end),
     scan.policy_generation}
  end

  defp api_status("clean"), do: "clean"
  defp api_status("matched"), do: "matched"
  defp api_status("partial"), do: "partial"
  defp api_status("failed"), do: "failed"
  defp api_status("running"), do: "pending"
  defp api_status(_), do: "pending"
end
