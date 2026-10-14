defmodule StarView.ElementsTest do
  use ExUnit.Case, async: true

  alias StarView.Elements

  test "formats a minimal element patch" do
    assert Elements.format_patch(~s(<div id="count">1</div>)) ==
             """
             event: datastar-patch-elements
             data: elements <div id="count">1</div>

             """
  end

  test "CR-only HTML lines retain their elements prefix without forging SSE frames" do
    event = Elements.format_patch("<div id=\"count\">a\rb</div>")

    assert event ==
             "event: datastar-patch-elements\ndata: elements <div id=\"count\">a\ndata: elements b</div>\n\n"

    assert length(Regex.scan(~r/^event:/m, event)) == 1
    refute event =~ "\r"
  end

  test "formats all non-default element options in ADR order" do
    assert Elements.format_patch(
             """
             <svg><circle id="dot"></circle></svg>
             """,
             selector: "#vis",
             mode: :append,
             use_view_transition: true,
             namespace: :svg,
             event_id: "event1",
             retry_duration: 2000
           ) ==
             """
             event: datastar-patch-elements
             id: event1
             retry: 2000
             data: selector #vis
             data: mode append
             data: useViewTransition true
             data: namespace svg
             data: elements <svg><circle id="dot"></circle></svg>
             data: elements 

             """
  end

  test "formats removals without element content" do
    assert Elements.format_remove("#old") ==
             """
             event: datastar-patch-elements
             data: selector #old
             data: mode remove

             """
  end

  test "remove helpers keep remove mode even when opts include a mode" do
    assert Elements.format_remove("#old", mode: :outer) ==
             """
             event: datastar-patch-elements
             data: selector #old
             data: mode remove

             """
  end

  test "rejects invalid modes" do
    assert_raise ArgumentError, fn ->
      Elements.format_patch("<div></div>", mode: :sideways)
    end
  end
end
