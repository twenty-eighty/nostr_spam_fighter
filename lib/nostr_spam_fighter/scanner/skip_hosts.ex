defmodule NostrSpamFighter.Scanner.SkipHosts do
  @moduledoc """
  Hosts whose URLs are matched without following redirects.

  The database is the source of truth. An ETS set is kept in sync for the
  scanner hot path. Application config is the seed list for an empty table
  and the fallback used in tests before the cache is loaded.
  """

  import Ecto.Query

  alias NostrSpamFighter.Repo
  alias NostrSpamFighter.Scanner.SkipRedirectHost

  @table :nsf_skip_redirect_hosts

  def setup do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true
        ])

      _tid ->
        :ok
    end

    :ok
  end

  def list do
    Repo.all(from h in SkipRedirectHost, order_by: h.host)
  end

  def get!(id), do: Repo.get!(SkipRedirectHost, id)

  def change(%SkipRedirectHost{} = row, attrs \\ %{}) do
    SkipRedirectHost.changeset(row, attrs)
  end

  def create(attrs) do
    %SkipRedirectHost{}
    |> SkipRedirectHost.changeset(attrs)
    |> Repo.insert()
    |> tap_reload()
  end

  def delete(%SkipRedirectHost{} = row) do
    row
    |> Repo.delete()
    |> tap_reload()
  end

  def member?(host) when is_binary(host) do
    MapSet.member?(hosts(), host)
  end

  def member?(_), do: false

  def hosts do
    setup()

    case :ets.lookup(@table, :hosts) do
      [{:hosts, %MapSet{} = set}] -> set
      _ -> MapSet.new(config_hosts())
    end
  end

  def reload do
    put_hosts(Repo.all(from h in SkipRedirectHost, select: h.host))
  end

  def reset_to_config do
    put_hosts(config_hosts())
  end

  def ensure_defaults do
    setup()

    Enum.each(config_hosts(), fn host ->
      %SkipRedirectHost{}
      |> SkipRedirectHost.changeset(%{host: host})
      |> Repo.insert(on_conflict: :nothing, conflict_target: :host)
    end)

    reload()
    list()
  end

  def config_hosts do
    Application.get_env(:nostr_spam_fighter, :skip_redirect_hosts, [])
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp put_hosts(hosts) do
    setup()
    :ets.insert(@table, {:hosts, MapSet.new(hosts)})
    :ok
  end

  defp tap_reload({:ok, row}) do
    reload()
    {:ok, row}
  end

  defp tap_reload(error), do: error
end
