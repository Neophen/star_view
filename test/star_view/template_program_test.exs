defmodule StarView.TemplateProgramTest do
  use ExUnit.Case, async: true

  alias StarView.Template
  alias StarView.Template.HTML
  alias StarView.Template.Node
  alias StarView.Template.Patch
  alias StarView.Template.Program
  alias StarView.Template.Renderer
  alias StarView.Template.Runtime
  alias StarView.TemplateProgramTest.Counted
  alias StarView.TemplateTest.Components

  # Hand-written stand-ins for compiler output: one function owns the static
  # markup, the node tree and the key, and escapes values through the runtime.

  test "a compiled program renders the same markup as its materialized tree" do
    template = card("card-1", "Hello")

    assert Template.to_html(template) ==
             ~s(<article class="card" id="card-1"><h2>Hello</h2></article>)

    assert Template.to_html(materialized(template)) == Template.to_html(template)
  end

  test "nodes/1 expands nested programs, components and template lists" do
    list = [card("a", "A"), ?x, [card("b", "B")]]
    child = %Program{run: &card_run/2, values: {"child", "Child"}}
    children = [child, Node.component(card("inner", "Inner")), Node.value(list)]
    outer = %Template{fingerprint: "outer", nodes: [Node.element("main", [], children)]}

    nodes = Template.nodes(outer)
    refute program?(nodes)
    assert Template.to_html(%Template{nodes: nodes}) == Template.to_html(outer)

    assert [%Node{children: [%Node{tag: "article"}, component, value]}] = nodes
    assert %Node{kind: :component, value: %Template{program: nil, nodes: [_]}} = component
    assert %Node{value: [%Template{program: nil}, ?x, [%Template{program: nil}]]} = value
  end

  test "a template holds exactly one representation" do
    program = %Program{run: &card_run/2, values: {"x", "y"}}
    both = %Template{nodes: [], program: program}
    neither = %Template{nodes: nil, program: nil}
    mutated = %{card("x", "y") | nodes: [Node.text("forged")]}

    Enum.each([both, neither, mutated], &assert_invalid_representation/1)

    assert Template.to_html(%Template{}) == ""
  end

  test "tampered values are escaped and validated on every render" do
    template = card(~s(x" onclick="evil), "<script>alert(1)</script>")
    html = Template.to_html(template)

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ ~s(id="x&quot; onclick=&quot;evil")
    assert Template.to_html(materialized(template)) == html

    legacy = %Phoenix.LiveView.Rendered{static: [""], dynamic: fn _ -> [] end, fingerprint: 0}
    assert_raise ArgumentError, ~r/legacy HEEx/, fn -> render_values({"ok", legacy}) end

    assert_raise ArgumentError, ~r/attribute value/, fn ->
      render_values({card("a", "b"), "t"})
    end
  end

  test "malformed values and programs raise ArgumentError" do
    short = compiled("card", &card_run/2, {"only"})
    assert_raise ArgumentError, "invalid compiled ~STAR values", fn -> Template.to_html(short) end
    assert_raise ArgumentError, "invalid compiled ~STAR values", fn -> Template.nodes(short) end

    assert_raise ArgumentError, "invalid compiled ~STAR values", fn ->
      Program.node_key(short.program)
    end

    listed = compiled("card", &card_run/2, ["a", "b"])
    unary = compiled("card", &String.upcase/1, {"a", "b"})

    assert_raise ArgumentError, ~r/invalid compiled ~STAR program/, fn ->
      Template.to_html(listed)
    end

    assert_raise ArgumentError, ~r/invalid compiled ~STAR program/, fn ->
      Template.to_html(unary)
    end

    broken = compiled("broken", &broken_run/2, {})
    assert_raise ArgumentError, ~r/must return a node list/, fn -> Template.nodes(broken) end
  end

  test "the program function owns all static structure" do
    assert Program.__struct__() |> Map.keys() |> Enum.sort() == [:__struct__, :run, :values]

    nodes = Template.nodes(card("a", ~s(<p id="x">forged</p>)))
    assert [%Node{tag: "article", children: [%Node{tag: "h2", children: [text]}]}] = nodes
    assert %Node{kind: :value, value: ~s(<p id="x">forged</p>)} = text
  end

  test "mixed manual and compiled snapshots diff like their materialized trees" do
    previous = mixed("Old")
    next = mixed("New")
    expected = ~s(<article class="card" id="card"><h2>New</h2></article>)

    assert {:ok, [%Patch{selector: "#card", elements: ^expected}]} = Template.diff(previous, next)

    assert Template.diff(previous, next) ==
             Template.diff(materialized(previous), materialized(next))

    assert {:ok, [%Patch{selector: "#card"}]} =
             Template.diff(card("card", "A"), card("card", "B"))
  end

  test "diff resets before materializing and materializes each snapshot once" do
    spy = compiled("spy", &spy_run/2, {self()})

    assert Template.diff(nil, spy) == {:reset, :initial}
    assert Template.diff(card("a", "b"), spy) == {:reset, :template_changed}
    refute_received :nodes

    assert Template.diff(spy, spy) == {:ok, []}
    assert_received :nodes
    assert_received :nodes
    refute_received :nodes
  end

  test "rendering runs the program once and never materializes" do
    assert Template.to_html(compiled("spy", &spy_run/2, {self()})) == "<p>spy</p>"
    assert_received :render
    refute_received :render
    refute_received :nodes
  end

  test "keyed collections read program keys without materializing" do
    items = [item("a", "A"), item("b", "B")]
    keyed = Runtime.keyed(items, %{})

    assert %Node{kind: :keyed, children: ^items} = keyed
    refute_received {:materialized, _key}

    html = Template.to_html(%Template{nodes: [keyed]})
    assert html == ~s(<li id="item-a">A</li><li id="item-b">B</li>)

    assert_raise ArgumentError, "~STAR :key values must not be nil", fn ->
      Runtime.keyed([item(nil, "A")], %{})
    end

    assert_raise ArgumentError, "~STAR :key values must be unique within a collection", fn ->
      Runtime.keyed([item("a", "A"), item("a", "B")], %{})
    end

    assert %Node{kind: :keyed} = Runtime.keyed([Node.fragment([], "manual")], %{})
  end

  test "keyed program items diff like their materialized trees" do
    previous = list([item("a", "A"), item("b", "B")])
    changed = list([item("a", "A"), item("b", "C")])
    reordered = list([item("b", "B"), item("a", "A")])

    assert {:ok, [%Patch{selector: "#item-b"}]} = Template.diff(previous, changed)
    assert {:ok, [%Patch{selector: "#list"}]} = Template.diff(previous, reordered)

    assert Template.diff(previous, changed) ==
             Template.diff(materialized(previous), materialized(changed))
  end

  test "compiled STAR templates match their materialized trees" do
    items = [%{id: "a", title: "A", visible: true}, %{id: "b", title: "B", visible: false}]

    templates = [
      Components.page(%{title: "Card", name: "<b>"}),
      Components.directives(%{items: items}),
      Components.conditional(%{shown: true, name: "Name"}),
      Components.escaped(%{disabled: true, class: "two", rest: [data: [x: "y"]], value: "<&>"}),
      Components.multiple_slots(%{})
    ]

    Enum.each(templates, &assert_matches_materialized/1)

    previous = Components.counter(%{count: 1, title: "Title"})
    next = Components.counter(%{count: 2, title: "Title"})
    assert {:ok, [%Patch{selector: "#counter"}]} = Template.diff(previous, next)

    assert Template.diff(previous, next) ==
             Template.diff(materialized(previous), materialized(next))
  end

  test "compiled expressions run once while building and never while rendering or diffing" do
    template = Counted.page(%{})
    assert Enum.frequencies(evaluated()) == %{title: 1, text: 1, items: 1}

    Template.to_html(template)
    Template.nodes(template)
    Template.diff(template, template)
    assert evaluated() == []
  end

  # Depends on the Stage 1 compiler binding expressions in document order.
  test "compiled expressions evaluate in document order" do
    Counted.page(%{})
    assert evaluated() == [:title, :text, :items]
  end

  defp assert_invalid_representation(template) do
    assert_raise ArgumentError, ~r/StarView.Template/, fn -> Template.to_html(template) end
    assert_raise ArgumentError, ~r/StarView.Template/, fn -> Template.nodes(template) end
    assert_raise ArgumentError, ~r/StarView.Template/, fn -> Template.diff(template, template) end
  end

  defp assert_matches_materialized(template) do
    refute program?(Template.nodes(template))
    assert Template.to_html(materialized(template)) == Template.to_html(template)
  end

  defp compiled(fingerprint, run, values),
    do: %Template{
      fingerprint: fingerprint,
      nodes: nil,
      program: %Program{run: run, values: values}
    }

  defp materialized(template), do: %{template | nodes: Template.nodes(template), program: nil}

  defp card(id, title), do: compiled("card", &card_run/2, {id, title})
  defp render_values(values), do: "card" |> compiled(&card_run/2, values) |> Template.to_html()
  defp item(key, title), do: %Program{run: &item_run/2, values: {key, "item-#{key}", title}}

  defp mixed(title) do
    child = %Program{run: &card_run/2, values: {"card", title}}
    main = Node.element("main", [{:static, "id", "main", "\""}], [child, Node.text("<hr>")])
    %Template{fingerprint: "mixed", nodes: [main]}
  end

  defp list(items) do
    ul = Node.element("ul", [{:static, "id", "list", "\""}], [Runtime.keyed(items, %{})])
    %Template{fingerprint: "list", nodes: [ul]}
  end

  defp card_run(:render, {id, title}) do
    attribute = HTML.attribute({:dynamic, "id", id})
    [~s(<article class="card"), attribute, "><h2>", Renderer.value(title), "</h2></article>"]
  end

  defp card_run(:nodes, {id, title}) do
    attrs = [{:static, "class", "card", "\""}, {:dynamic, "id", id}]
    [Node.element("article", attrs, [Node.element("h2", [], [Node.value(title)])])]
  end

  defp card_run(:key, {_id, _title}), do: nil
  defp card_run(_mode, _values), do: raise(ArgumentError, "invalid compiled ~STAR values")

  defp item_run(:render, {_key, id, title}),
    do: ["<li", HTML.attribute({:dynamic, "id", id}), ">", Renderer.value(title), "</li>"]

  defp item_run(:nodes, {key, id, title}) do
    send(self(), {:materialized, key})
    [Node.fragment([Node.element("li", [{:dynamic, "id", id}], [Node.value(title)])], key)]
  end

  defp item_run(:key, {key, _id, _title}), do: key
  defp item_run(_mode, _values), do: raise(ArgumentError, "invalid compiled ~STAR values")

  defp spy_run(:render, {pid}), do: tap("<p>spy</p>", fn _ -> send(pid, :render) end)

  defp spy_run(:nodes, {pid}),
    do: tap([Node.element("p", [], [Node.text("spy")])], fn _ -> send(pid, :nodes) end)

  defp spy_run(:key, {_pid}), do: nil
  defp spy_run(_mode, _values), do: raise(ArgumentError, "invalid compiled ~STAR values")

  defp broken_run(:nodes, {}), do: :not_a_list
  defp broken_run(_mode, _values), do: raise(ArgumentError, "invalid compiled ~STAR values")

  defp program?(%Program{}), do: true
  defp program?(%_{} = struct), do: struct |> Map.from_struct() |> Map.values() |> program?()
  defp program?(list) when is_list(list), do: Enum.any?(list, &program?/1)
  defp program?(_term), do: false

  defp evaluated(acc \\ []) do
    receive do
      {:evaluated, label} -> evaluated([label | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
