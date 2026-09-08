defmodule NostrSpamFighter.Nostr.LabelPublisher do
  @moduledoc """
  Builds and publishes NIP-32 kind 1985 labels.
  """

  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Policy.{Category, Namespace}
  alias NostrSpamFighter.Nostr.{EventRelay, Relay, Signer}
  alias NostrSpamFighter.Moderation.{PublishedLabel, PublishedLabelDelivery}

  @kind 1985

  def publish(event_id, category_id) do
    category = Repo.get!(Category, category_id)
    source_relay = source_relay(event_id)

    case existing_label(event_id, category_id) do
      %PublishedLabel{status: "active"} = label ->
        deliver(label)

      %PublishedLabel{signed_event: event} = label ->
        deliver(%{label | signed_event: event})

      nil ->
        with {:ok, signed} <- build_and_sign(event_id, category.slug, source_relay) do
          {:ok, label} =
            %PublishedLabel{}
            |> PublishedLabel.changeset(%{
              event_id: event_id,
              category_id: category_id,
              label_event_id: signed["id"],
              signed_event: signed,
              status: "pending"
            })
            |> Repo.insert()

          deliver(label)
        end
    end
  end

  def withdraw(event_id, category_id) do
    case existing_label(event_id, category_id) do
      nil ->
        :ok

      label ->
        label
        |> PublishedLabel.changeset(%{
          status: "withdrawn",
          withdrawn_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  def build_tags(event_id, slug, relay_hint) do
    namespace = Namespace.content()

    [
      ["L", namespace],
      ["l", slug, namespace],
      ["e", event_id, relay_hint || ""]
    ]
  end

  defp build_and_sign(event_id, slug, relay_hint) do
    Signer.sign(@kind, "", build_tags(event_id, slug, relay_hint))
  end

  defp deliver(%PublishedLabel{} = label) do
    relays = write_relays()

    Enum.each(relays, fn url ->
      result = Nostr.Client.publish([url], label.signed_event, min_ok: 1)

      {status, error} =
        case result do
          {:ok, _} -> {"ok", nil}
          {:error, reason} -> {"error", inspect(reason)}
        end

      %PublishedLabelDelivery{}
      |> PublishedLabelDelivery.changeset(%{
        published_label_id: label.id,
        relay_url: url,
        status: status,
        error: error,
        attempted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert(
        on_conflict: [set: [status: status, error: error, updated_at: DateTime.utc_now()]],
        conflict_target: [:published_label_id, :relay_url]
      )
    end)

    overall = if relays != [] and all_ok?(label.id), do: "active", else: "pending"

    label
    |> PublishedLabel.changeset(%{status: overall})
    |> Repo.update()
  end

  defp all_ok?(label_id) do
    Repo.exists?(
      from d in PublishedLabelDelivery,
        where: d.published_label_id == ^label_id and d.status == "ok"
    )
  end

  defp existing_label(event_id, category_id) do
    Repo.get_by(PublishedLabel, event_id: event_id, category_id: category_id)
  end

  defp source_relay(event_id) do
    Repo.one(from r in EventRelay, where: r.event_id == ^event_id, select: r.relay_url, limit: 1)
  end

  defp write_relays do
    Repo.all(from r in Relay, where: r.enabled == true and r.write_enabled == true, select: r.url)
  end
end
