defmodule Mix.Tasks.Nsf.BootstrapAdmin do
  @shortdoc "Creates the initial admin from INITIAL_ADMIN_PUBKEY"
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case NostrSpamFighter.Accounts.ensure_bootstrap_admin() do
      {:ok, :created} ->
        Mix.shell().info("Created bootstrap admin")

      {:ok, :exists} ->
        Mix.shell().info("Admin already exists")

      {:error, :invalid_pubkey} ->
        Mix.raise("INITIAL_ADMIN_PUBKEY is required")

      {:error, reason} ->
        Mix.raise("Could not create admin: #{inspect(reason)}")
    end
  end
end
