defmodule StarView.TemplateClausesTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import StarView.Template.Sigils

  alias StarView.Template

  test "case patterns, guards and bound variables retain Phoenix HTML behavior" do
    Enum.each([{:ok, "<Title>"}, {:ok, 42}, :error], &assert_case_parity/1)
  end

  test "cond selects a branch and preserves escaping" do
    Enum.each([-1, 0, 2], &assert_cond_parity/1)
  end

  test "a changed value within one clause patches its stable child" do
    previous = case_star(%{result: {:ok, "First"}})
    next = case_star(%{result: {:ok, "Second"}})
    assert {:ok, [patch]} = Template.diff(previous, next)
    assert patch.selector == "#title"
    assert patch.elements == "<p id=\"title\">Second</p>"
  end

  test "switching clauses bubbles to the existing ancestor" do
    previous = case_star(%{result: {:ok, "First"}})
    next = case_star(%{result: :error})
    assert {:ok, [patch]} = Template.diff(previous, next)
    assert patch.selector == "#content"
    assert patch.elements =~ "Unavailable"
  end

  test "unmatched case and cond keep ordinary Elixir failures" do
    assert_raise CaseClauseError, fn -> unmatched_case(%{value: :missing}) end
    assert_raise CondClauseError, fn -> unmatched_cond(%{value: false}) end
  end

  test "parser-normalized EEx comments stay absent from HTML" do
    assert Template.to_html(commented(%{title: "Shown"})) == "<p>Shown</p>"
  end

  test "formatting and interpolation hints affect compilation without becoming DOM attributes" do
    html = Template.to_html(hints(%{title: "Shown"}))
    assert html =~ "<p>Shown</p>"
    assert html =~ "<code>{literal}</code>"
    refute html =~ "phx-no-"
  end

  defp hints(assigns) do
    ~STAR"""
    <p phx-no-format>{@title}</p><code phx-no-curly-interpolation>{literal}</code>
    """
  end

  test "assigns inside guards use guard-safe map access, including a failed guard" do
    assert Template.to_html(guarded(%{value: 5, limit: 3})) =~ "Above"
    assert Template.to_html(guarded(%{value: 2, limit: 3})) =~ "Other"
    assert Template.to_html(guarded(%{value: 5})) =~ "Other"
  end

  test "an inline opening clause fails clearly rather than silently disappearing" do
    source = "<%= case @value do :a -> %><% :b -> %>B<% end %>"
    module = Module.concat(__MODULE__, InvalidOpening)

    code =
      "defmodule #{inspect(module)} do import StarView.Template.Sigils; def render(assigns), do: ~STAR\"#{source}\" end"

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_invalid_opener(code)
    end)
  end

  defp assert_invalid_opener(code) do
    assert_raise CompileError, ~r/~STAR:.*(separate EEx tags|non-output EEx)/, fn ->
      Code.compile_string(code)
    end
  end

  test "conditional named slots stay native and bubble when inserted" do
    components = StarView.TemplateTest.Components
    hidden = components.optional_slot_page(%{title: "Card", shown: false})
    shown = components.optional_slot_page(%{title: "Card", shown: true})
    refute Template.to_html(hidden) =~ "<button"
    assert Template.to_html(shown) =~ "<button id=\"action\">Action</button>"
    assert {:ok, [patch]} = Template.diff(hidden, shown)
    assert patch.selector == "#card"
  end

  defp guarded(assigns) do
    ~STAR"""
    <section id="guarded">
      <%= case @value do %>
        <%!-- Before the first clause --%>
        <% number when number > @limit -> %>
          Above
        <% _ -> %>
          Other
      <% end %>
    </section>
    """
  end

  defp commented(assigns) do
    ~STAR"""
    <p><%!-- Invisible --%>{@title}</p>
    """
  end

  defp assert_case_parity(value) do
    assigns = %{result: value}
    assert normalize(Template.to_html(case_star(assigns))) == normalize(html(case_heex(assigns)))
  end

  defp assert_cond_parity(value) do
    assigns = %{value: value, title: "<Title>"}
    assert normalize(Template.to_html(cond_star(assigns))) == normalize(html(cond_heex(assigns)))
  end

  # Source formatting and LiveView's root marker are outside native branch semantics.
  defp normalize(html) do
    html = String.replace(html, " phx-r", "")
    html = Regex.replace(~r/>\s+/, html, ">")
    Regex.replace(~r/\s+</, html, "<")
  end

  defp html(value), do: value |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp case_star(assigns) do
    ~STAR"""
    <section id="content">
      <%= case @result do %>
        <% {:ok, title} when is_binary(title) -> %>
          <p id="title">{title}</p>
        <% {:ok, number} -> %>
          <p>{number}</p>
        <% _ -> %>
          Unavailable
      <% end %>
    </section>
    """
  end

  defp case_heex(assigns) do
    ~H"""
    <section id="content"><%= case @result do %><% {:ok, title} when is_binary(title) -> %><p id="title">{title}</p><% {:ok, number} -> %><p>{number}</p><% _ -> %>Unavailable<% end %></section>
    """
  end

  defp cond_star(assigns) do
    ~STAR"""
    <section id="content">
      <%= cond do %>
        <% @value > 0 -> %>
          <p id="positive">{@title}</p>
        <% @value == 0 -> %>
          Zero
        <% true -> %>
          Negative
      <% end %>
    </section>
    """
  end

  defp cond_heex(assigns) do
    ~H"""
    <section id="content"><%= cond do %><% @value > 0 -> %><p id="positive">{@title}</p><% @value == 0 -> %>Zero<% true -> %>Negative<% end %></section>
    """
  end

  defp unmatched_case(assigns) do
    ~STAR"""
    <%= case @value do %>
      <% :present -> %>
        Present
    <% end %>
    """
  end

  defp unmatched_cond(assigns) do
    ~STAR"""
    <%= cond do %>
      <% @value -> %>
        Present
    <% end %>
    """
  end
end
