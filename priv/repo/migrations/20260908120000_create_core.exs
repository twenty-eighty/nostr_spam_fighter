defmodule NostrSpamFighter.Repo.Migrations.CreateCore do
  use Ecto.Migration

  def change do
    Oban.Migration.up(version: 14)

    create table(:content_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :enabled, :boolean, null: false, default: true
      add :blocks_serving, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:content_categories, [:slug])

    create table(:blocklists, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :category_id, references(:content_categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :source_type, :string, null: false
      add :source_url, :string
      add :format, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :refresh_interval_s, :integer, null: false, default: 86_400
      add :last_attempt_at, :utc_datetime
      add :last_success_at, :utc_datetime
      add :next_refresh_at, :utc_datetime
      add :etag, :string
      add :last_modified, :string
      add :active_version_id, :binary_id
      timestamps(type: :utc_datetime)
    end

    create index(:blocklists, [:category_id])

    create table(:blocklist_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :blocklist_id, references(:blocklists, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false
      add :checksum, :string
      add :entry_count, :integer, null: false, default: 0
      add :fetched_at, :utc_datetime
      add :validated_at, :utc_datetime
      add :activated_at, :utc_datetime
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create index(:blocklist_versions, [:blocklist_id])

    create table(:blocklist_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :blocklist_version_id,
          references(:blocklist_versions, type: :binary_id, on_delete: :delete_all), null: false

      add :rule_type, :string, null: false
      add :original_value, :text, null: false
      add :normalized_value, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:blocklist_entries, [:blocklist_version_id])
    create index(:blocklist_entries, [:normalized_value])

    create table(:policy_generations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :generation, :bigint, null: false
      add :reason, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:policy_generations, [:generation])

    create table(:nostr_relays, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :read_enabled, :boolean, null: false, default: true
      add :write_enabled, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:nostr_relays, [:url])

    create table(:nostr_events, primary_key: false) do
      add :event_id, :string, primary_key: true
      add :kind, :integer, null: false
      add :pubkey, :string, null: false
      add :created_at, :bigint, null: false
      add :d_tag, :string
      add :article_address, :string
      add :raw_event, :map, null: false
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
    end

    create index(:nostr_events, [:kind, :pubkey, :d_tag])
    create index(:nostr_events, [:article_address])

    create table(:event_relays, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_id,
          references(:nostr_events, column: :event_id, type: :string, on_delete: :delete_all),
          null: false

      add :relay_url, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_relays, [:event_id, :relay_url])

    create table(:scans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_id,
          references(:nostr_events, column: :event_id, type: :string, on_delete: :delete_all),
          null: false

      add :policy_generation, :bigint, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :urls_discovered, :integer, null: false, default: 0
      add :urls_resolved, :integer, null: false, default: 0
      add :redirects_followed, :integer, null: false, default: 0
      add :matches_found, :integer, null: false, default: 0
      add :error, :text
      add :scanner_version, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:scans, [:event_id])
    create index(:scans, [:status])

    create table(:url_occurrences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scan_id, references(:scans, type: :binary_id, on_delete: :delete_all), null: false
      add :original_url, :text, null: false
      add :normalized_url, :text, null: false
      add :hostname, :string
      add :source_type, :string, null: false
      add :source_location, :string
      timestamps(type: :utc_datetime)
    end

    create index(:url_occurrences, [:scan_id])
    create index(:url_occurrences, [:normalized_url])

    create table(:url_resolutions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :url_occurrence_id,
          references(:url_occurrences, type: :binary_id, on_delete: :delete_all), null: false

      add :status, :string, null: false
      add :final_url, :text
      add :final_hostname, :string
      add :http_status, :integer
      add :redirect_count, :integer, null: false, default: 0
      add :duration_ms, :integer
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create index(:url_resolutions, [:url_occurrence_id])

    create table(:redirect_hops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :url_resolution_id,
          references(:url_resolutions, type: :binary_id, on_delete: :delete_all), null: false

      add :hop_index, :integer, null: false
      add :url, :text, null: false
      add :hostname, :string
      add :resolved_ip, :string
      add :http_status, :integer
      add :location, :text
      add :duration_ms, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:redirect_hops, [:url_resolution_id])

    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scan_id, references(:scans, type: :binary_id, on_delete: :delete_all), null: false

      add :url_occurrence_id,
          references(:url_occurrences, type: :binary_id, on_delete: :nilify_all)

      add :redirect_hop_id, references(:redirect_hops, type: :binary_id, on_delete: :nilify_all)

      add :category_id, references(:content_categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :blocklist_id, references(:blocklists, type: :binary_id, on_delete: :restrict),
        null: false

      add :blocklist_version_id,
          references(:blocklist_versions, type: :binary_id, on_delete: :restrict), null: false

      add :blocklist_entry_id,
          references(:blocklist_entries, type: :binary_id, on_delete: :restrict), null: false

      add :matched_url, :text
      add :matched_hostname, :string
      add :match_type, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:matches, [:scan_id])
    create index(:matches, [:category_id])

    create table(:classifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scan_id, references(:scans, type: :binary_id, on_delete: :delete_all), null: false
      add :event_id, :string, null: false

      add :category_id, references(:content_categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:classifications, [:scan_id, :category_id])
    create index(:classifications, [:event_id])

    create table(:article_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :integer, null: false
      add :pubkey, :string, null: false
      add :d_tag, :string, null: false
      add :address, :string, null: false
      add :current_event_id, :string
      add :current_event_created_at, :bigint
      timestamps(type: :utc_datetime)
    end

    create unique_index(:article_addresses, [:kind, :pubkey, :d_tag])
    create unique_index(:article_addresses, [:address])

    create table(:article_moderation_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_address_id,
          references(:article_addresses, type: :binary_id, on_delete: :delete_all), null: false

      add :event_id, :string
      add :scan_id, references(:scans, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false
      add :blacklisted, :boolean
      add :policy_generation, :bigint
      timestamps(type: :utc_datetime)
    end

    create unique_index(:article_moderation_states, [:article_address_id])

    create table(:article_moderation_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_moderation_state_id,
          references(:article_moderation_states, type: :binary_id, on_delete: :delete_all),
          null: false

      add :category_id, references(:content_categories, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slug, :string, null: false
    end

    create unique_index(:article_moderation_categories, [
             :article_moderation_state_id,
             :category_id
           ])

    create table(:published_labels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, :string, null: false

      add :category_id, references(:content_categories, type: :binary_id, on_delete: :restrict),
        null: false

      add :label_event_id, :string, null: false
      add :signed_event, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :withdrawn_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:published_labels, [:event_id, :category_id])

    create table(:published_label_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :published_label_id,
          references(:published_labels, type: :binary_id, on_delete: :delete_all), null: false

      add :relay_url, :string, null: false
      add :status, :string, null: false
      add :error, :text
      add :attempted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:published_label_deliveries, [:published_label_id, :relay_url])

    create table(:admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pubkey, :string, null: false
      add :name, :string
      add :enabled, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:pubkey])

    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :key_prefix, :string, null: false
      add :secret_hash, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :enabled, :boolean, null: false, default: true
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :last_used_ip, :string
      add :created_by_admin_id, references(:admins, type: :binary_id, on_delete: :nilify_all)
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_keys, [:key_prefix])
  end
end
