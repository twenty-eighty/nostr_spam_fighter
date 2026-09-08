defmodule NostrSpamFighter.Relays do
  import Ecto.Query
  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Nostr.Relay

  def list_relays, do: Repo.all(from r in Relay, order_by: r.url)

  def list_read_urls do
    Repo.all(from r in Relay, where: r.enabled == true and r.read_enabled == true, select: r.url)
  end

  def get_relay!(id), do: Repo.get!(Relay, id)

  def create_relay(attrs) do
    %Relay{} |> Relay.changeset(attrs) |> Repo.insert() |> maybe_reconnect()
  end

  def update_relay(%Relay{} = relay, attrs) do
    relay |> Relay.changeset(attrs) |> Repo.update() |> maybe_reconnect()
  end

  def change_relay(%Relay{} = relay, attrs \\ %{}), do: Relay.changeset(relay, attrs)

  defp maybe_reconnect({:ok, relay}) do
    if NostrSpamFighter.Nostr.RelayIngest.running?() do
      NostrSpamFighter.Nostr.RelayIngest.reconnect()
    end

    {:ok, relay}
  end

  defp maybe_reconnect(error), do: error
end
