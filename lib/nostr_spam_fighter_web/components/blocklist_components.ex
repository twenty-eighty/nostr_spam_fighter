defmodule NostrSpamFighterWeb.BlocklistComponents do
  use NostrSpamFighterWeb, :html

  alias NostrSpamFighter.Policy.{Blocklist, Importer}

  attr :list, Blocklist, required: true
  attr :id, :string, default: nil
  attr :error_id, :string, default: nil
  attr :progress, :map, default: nil

  def refresh_status(assigns) do
    assigns =
      assign(assigns, :id, assigns.id || "blocklist-progress-#{assigns.list.id}")

    ~H"""
    <div
      :if={
        @list.refresh_status in ~w(queued downloading importing failed rejected) or
          Blocklist.show_refresh_error?(@list)
      }
      id={@id}
      class="inline-flex items-center gap-2"
    >
      <span
        :if={Blocklist.refresh_label(@list)}
        class={[
          "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-sm font-medium",
          @list.refresh_status == "downloading" &&
            "bg-sky-500/15 text-sky-800 dark:text-sky-200",
          @list.refresh_status == "importing" &&
            "bg-violet-500/15 text-violet-800 dark:text-violet-200",
          @list.refresh_status == "queued" &&
            "bg-amber-500/15 text-amber-800 dark:text-amber-200",
          @list.refresh_status in ~w(failed rejected) &&
            "bg-red-500/15 text-red-800 dark:text-red-200"
        ]}
      >
        <.icon
          name={status_icon(@list.refresh_status)}
          class={[
            "size-3.5",
            @list.refresh_status in ~w(downloading importing) && "animate-spin"
          ]}
        />
        {Blocklist.refresh_label(@list)}
      </span>
      <div
        :if={@progress && @list.refresh_status in ~w(downloading importing)}
        id={"blocklist-download-#{@list.id}"}
        class="min-w-36 max-w-48"
      >
        <div class="h-1.5 overflow-hidden rounded-full bg-zinc-200 dark:bg-zinc-700">
          <div
            :if={is_number(@progress.percent)}
            class={[
              "h-full rounded-full transition-[width] duration-200",
              @list.refresh_status == "importing" && "bg-violet-500",
              @list.refresh_status != "importing" && "bg-sky-500"
            ]}
            style={"width: #{bar_width(@progress.percent)}%"}
          />
          <div
            :if={not is_number(@progress.percent)}
            class={[
              "h-full w-1/3 animate-pulse rounded-full",
              @list.refresh_status == "importing" && "bg-violet-500/80",
              @list.refresh_status != "importing" && "bg-sky-500/80"
            ]}
          />
        </div>
        <p
          id={"blocklist-download-speed-#{@list.id}"}
          class="mt-0.5 text-[11px] leading-none tabular-nums opacity-70"
        >
          {format_progress(@progress)}
        </p>
      </div>
      <span
        :if={Blocklist.show_refresh_error?(@list)}
        id={@error_id || "blocklist-error-#{@list.id}"}
        class="text-error text-sm"
      >
        {@list.last_error}
      </span>
    </div>
    """
  end

  defp status_icon("queued"), do: "hero-clock"
  defp status_icon(status) when status in ~w(failed rejected), do: "hero-exclamation-triangle"
  defp status_icon(_), do: "hero-arrow-path"

  defp bar_width(percent) when is_number(percent),
    do: percent |> max(0) |> min(100) |> Float.round(1)

  defp format_progress(%{phase: "import", stage: stage, done: done, total: total})
       when is_integer(total) and total > 0 do
    "#{import_stage(stage)} #{Importer.format_count(done)} / #{Importer.format_count(total)}"
  end

  defp format_progress(%{phase: "import", stage: stage, done: done}) do
    "#{import_stage(stage)} #{Importer.format_count(done)}"
  end

  defp format_progress(%{bytes: bytes, total: total, bytes_per_sec: bps})
       when is_integer(total) and total > 0 do
    "#{Importer.format_bytes(bytes)} / #{Importer.format_bytes(total)} · #{speed(bps)}"
  end

  defp format_progress(%{bytes: bytes, bytes_per_sec: bps}) do
    "#{Importer.format_bytes(bytes)} · #{speed(bps)}"
  end

  defp speed(bps) when is_number(bps) and bps >= 0 do
    "#{Importer.format_bytes(round(bps))}/s"
  end

  defp speed(_), do: "0 B/s"

  defp import_stage("parsing"), do: "Parsing"
  defp import_stage("saving"), do: "Saving"
  defp import_stage(_), do: "Importing"
end
