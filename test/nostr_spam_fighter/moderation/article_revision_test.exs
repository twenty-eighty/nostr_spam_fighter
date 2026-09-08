defmodule NostrSpamFighter.Moderation.ArticleRevisionTest do
  use ExUnit.Case, async: true

  test "current revision uses created_at then event_id, not arrival order" do
    first = %{event_id: "bb", created_at: 50}
    current = %{current_event_id: "aa", current_event_created_at: 50}
    assert newer_revision?(first, current)

    older_evt = %{event_id: "zz", created_at: 10}
    refute newer_revision?(older_evt, current)
  end

  defp newer_revision?(event, current) do
    cond do
      is_nil(current.current_event_created_at) -> true
      event.created_at > current.current_event_created_at -> true
      event.created_at < current.current_event_created_at -> false
      event.event_id > (current.current_event_id || "") -> true
      true -> false
    end
  end
end
