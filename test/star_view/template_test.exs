defmodule StarView.TemplateTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]

  alias StarView.Template
  alias StarView.Template.Node
  alias StarView.Template.Patch

  describe "to_html/1" do
    test "escapes dynamic content and attribute values" do
      attrs = [{:dynamic, "title", ~s|" onmouseover="alert(1)|}]
      nodes = el("p", attrs, [value("<script>alert('x')</script>")])

      assert html(nodes) ==
               ~s|<p title="&quot; onmouseover=&quot;alert(1)">| <>
                 "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;</p>"
    end

    test "keeps literal entities and static delimiters verbatim" do
      attrs = [
        {:static, "title", "A &amp; &quot;B&quot;", "'"},
        {:static, "data-x", "it&#39;s", "\""}
      ]

      nodes = el("p", attrs, [Node.text("Tom &amp; Jerry &lt;3")])

      assert html(nodes) ==
               ~s(<p title='A &amp; &quot;B&quot;' data-x="it&#39;s">Tom &amp; Jerry &lt;3</p>)
    end

    test "rejects a static value containing its own delimiter" do
      assert_raise ArgumentError, ~r/delimiter/, fn ->
        html(el("p", [{:static, "title", "it's", "'"}], []))
      end
    end

    test "renders class lists and boolean attributes like HEEx" do
      attrs = [
        {:dynamic, "class", ["btn", nil, false, ["active"]]},
        {:dynamic, "disabled", true},
        {:dynamic, "hidden", false},
        {:dynamic, "title", nil},
        {:static, "required", nil, "\""}
      ]

      assert html(el("button", attrs, [])) ==
               ~s(<button class="btn active" disabled required></button>)

      empty = [{:dynamic, "class", nil}, {:dynamic, "style", false}]
      assert html(el("p", empty, [])) == ~s(<p class="" style=""></p>)
    end

    test "renders void elements without closing tags" do
      input = Node.element("input", [{:static, "type", "text", "\""}], [], %{void?: true})
      nodes = el("p", [], [Node.element("br", [], [], %{void?: true}), input])

      assert html(nodes) == ~s(<p><br><input type="text"></p>)

      assert_raise ArgumentError, ~r/void element <br>/, fn ->
        html(Node.element("br", [], [Node.text("x")], %{void?: true}))
      end
    end

    test "renders spread attributes like HEEx" do
      spread = [
        phx_click: "go",
        data: [user_id: 1, confirm: true, skip: nil],
        hidden: true,
        title: nil,
        class: ["a", "b"]
      ]

      assert html(el("div", [{:spread, spread}], [])) ==
               ~s(<div phx_click="go" data-user-id="1" data-confirm hidden class="a b"></div>)
    end

    test "rejects attribute names that could forge markup" do
      invalid = [
        [{:spread, [{"x onmouseover", "alert(1)"}]}],
        [{:spread, %{~s(x"y) => 1}}],
        [{:spread, [data: [{"a b", 1}]]}],
        [{:spread, [{{:safe, "onclick"}, "x"}]}],
        [{:spread, ["oops"]}],
        [{:dynamic, "a=b", "x"}],
        [{:dynamic, "title>", "x"}]
      ]

      Enum.each(invalid, &assert_invalid_attributes/1)
    end

    test "rejects invalid tag names" do
      assert_raise ArgumentError, ~r/invalid tag name/, fn ->
        html(el("div onclick=x", [], []))
      end
    end

    test "renders nested own templates and serializes through Phoenix HTML Safe" do
      inner = template(el("b", [], [value("<i>")]), "inner")
      outer = template(el("p", [], [value(inner), Node.component(inner), value([inner, "&"])]))

      assert Template.to_html(outer) ==
               "<p><b>&lt;i&gt;</b><b>&lt;i&gt;</b><b>&lt;i&gt;</b>&amp;</p>"

      assert inner |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string() ==
               "<b>&lt;i&gt;</b>"
    end

    test "rejects ordinary HEEx values instead of silently embedding them" do
      nodes = el("p", [id("legacy")], [Node.component(badge("<x>"))])
      assert_raise ArgumentError, ~r/legacy HEEx.*incompatible/, fn -> html(nodes) end
    end

    test "rejects legacy values in nested content and attributes with a conversion error" do
      Enum.each([:body, :list, :attribute, :spread, :class], &assert_legacy_rejected/1)
    end
  end

  describe "diff/2" do
    test "mixed template lists compare integers using iodata character semantics" do
      inner = template(el("b", [], [Node.text("Inner")]), "inner")
      previous = template(el("p", [id("mixed")], [value([inner, ?a])]))
      next = template(el("p", [id("mixed")], [value([inner, "97"])]))

      assert {:ok, [%Patch{selector: "#mixed", elements: html}]} = Template.diff(previous, next)
      assert html == ~s(<p id="mixed"><b>Inner</b>97</p>)
      same_html = template(el("p", [id("mixed")], [value([inner, "a"])]))
      assert {:ok, []} = Template.diff(previous, same_html)
    end

    test "resets without a baseline or when the template changed" do
      assert Template.diff(nil, list("A", "B")) == {:reset, :initial}

      changed = %{list("A", "B") | fingerprint: "other"}
      assert Template.diff(list("A", "B"), changed) == {:reset, :template_changed}
    end

    test "returns no patches for unchanged snapshots" do
      assert Template.diff(list("A", "B"), list("A", "B")) == {:ok, []}
    end

    test "patches only the changed addressable child" do
      assert Template.diff(list("A", "B"), list("A", "C")) ==
               {:ok,
                [
                  %Patch{
                    selector: "#b",
                    elements: ~s(<li id="b">C</li>),
                    mode: :outer,
                    namespace: :html
                  }
                ]}
    end

    test "patches an addressable element whose attributes changed" do
      assert {:ok, [patch]} = Template.diff(classes("x", "y"), classes("z", "y"))
      assert patch.selector == "#a"
      assert patch.elements == ~s(<li id="a" class="z">A</li>)
    end

    test "bubbles attribute changes without a target to the nearest ancestor" do
      assert {:ok, [patch]} = Template.diff(classes("x", "y"), classes("x", "z"))
      assert patch.selector == "#list"
      assert patch.elements =~ ~s(<li class="z">B</li>)
    end

    test "patches the existing ancestor when a branch is switched, inserted or removed" do
      assert {:ok, [patch]} = Template.diff(panel(:yes), panel(:no))
      assert patch.selector == "#panel"
      assert patch.elements == ~s(<section id="panel"><p id="no">No</p></section>)

      assert {:ok, [%Patch{selector: "#panel"}]} = Template.diff(panel(:none), panel(:yes))
      assert {:ok, [%Patch{selector: "#panel"}]} = Template.diff(panel(:yes), panel(:none))
    end

    test "patches the keyed parent when order or membership changes" do
      previous = rows([{1, "A"}, {2, "B"}])

      assert {:ok, [%Patch{selector: "#rows"} = patch]} =
               Template.diff(previous, rows([{2, "B"}, {1, "A"}]))

      assert patch.elements =~ ~s(<tr id="row-2"><td>B</td></tr><tr id="row-1">)
      assert {:ok, [%Patch{selector: "#rows"}]} = Template.diff(previous, rows([{1, "A"}]))
    end

    test "patches only the row whose content changed under the same keys" do
      assert Template.diff(rows([{1, "A"}, {2, "B"}]), rows([{1, "A"}, {2, "C"}])) ==
               {:ok, [%Patch{selector: "#row-2", elements: ~s(<tr id="row-2"><td>C</td></tr>)}]}
    end

    test "resets on duplicate or missing item keys" do
      assert Template.diff(rows([{1, "A"}]), rows([{1, "A"}, {1, "B"}])) ==
               {:reset, {:duplicate_key, 1}}

      missing =
        template(el("tbody", [id("rows")], [Node.keyed([Node.fragment([Node.text("x")])])]))

      assert Template.diff(rows([{1, "A"}]), missing) == {:reset, :missing_key}
    end

    test "resets when no addressable ancestor contains the change" do
      assert Template.diff(template(value("A")), template(value("B"))) ==
               {:reset, {:unaddressable, :value_changed}}

      assert Template.diff(
               template(el("p", [], [value("A")])),
               template(el("p", [], [value("B")]))
             ) ==
               {:reset, {:unaddressable, :value_changed}}
    end

    test "falls back past ids that are unsafe as selectors or that changed" do
      for child_id <- ["a:b", "a b", "a&amp;b", "1a"] do
        assert {:ok, [%Patch{selector: "#wrap"}]} =
                 Template.diff(wrapped([id(child_id)], "A"), wrapped([id(child_id)], "B"))
      end

      assert {:ok, [%Patch{selector: "#wrap"}]} =
               Template.diff(
                 wrapped([{:dynamic, "id", "a"}], "A"),
                 wrapped([{:dynamic, "id", "b"}], "A")
               )
    end

    test "never targets duplicate or ambiguous ids" do
      assert {:ok, [%Patch{selector: "#wrap"}]} = Template.diff(duplicates("A"), duplicates("B"))

      ambiguous = [id("a"), {:spread, [id: "b"]}]

      assert {:ok, [%Patch{selector: "#wrap"}]} =
               Template.diff(wrapped(ambiguous, "A"), wrapped(ambiguous, "B"))

      root_duplicates = fn label ->
        template([el("p", [id("dup")], [value(label)]), el("p", [id("dup")], [])])
      end

      assert Template.diff(root_duplicates.("A"), root_duplicates.("B")) ==
               {:reset, {:unaddressable, :value_changed}}
    end

    test "a patched ancestor replaces its descendants' patches" do
      assert {:ok, [patch]} = Template.diff(outer("a", "A"), outer("b", "B"))
      assert patch.selector == "#outer"
      assert patch.elements == ~s(<div id="outer" class="b"><p id="inner">B</p></div>)
    end

    test "walks nested own templates and bubbles fingerprint changes" do
      assert {:ok, [%Patch{selector: "#body"}]} = Template.diff(card("v1", "A"), card("v1", "B"))
      assert {:ok, [%Patch{selector: "#card"}]} = Template.diff(card("v1", "A"), card("v2", "B"))
    end

    test "rejects HEEx values while comparing snapshots" do
      previous = template(el("div", [id("box")], [value(badge("a"))]))
      next = template(el("div", [id("box")], [value(badge("b"))]))

      assert_raise ArgumentError, ~r/legacy HEEx.*incompatible/, fn ->
        Template.diff(previous, next)
      end
    end

    test "returns no patches when different shapes render the same HTML" do
      previous = template(el("div", [id("d")], [Node.branch(true, [Node.text("x")])]))
      next = template(el("div", [id("d")], [Node.branch(false, [Node.text("x")])]))

      assert Template.diff(previous, next) == {:ok, []}
    end

    test "targets an svg root but not its foreign descendants" do
      assert {:ok, [%Patch{selector: "#svg", namespace: :html} = patch]} =
               Template.diff(chart("1"), chart("2"))

      assert patch.elements == ~s(<svg id="svg"><circle id="dot" r="2"></circle></svg>)
    end

    test "does not target descendants of ignored, custom or browser-owned elements" do
      ignored = fn label ->
        host(el("div", [id("editor"), {:static, "data-ignore-morph", nil, "\""}], [inner(label)]))
      end

      rocket = fn label -> host(el("star-rocket", [id("rocket")], [inner(label)])) end

      owned = fn label ->
        host(Node.element("div", [id("owned")], [inner(label)], %{browser_owned?: true}))
      end

      assert {:ok, [%Patch{selector: "#host"}]} = Template.diff(ignored.("A"), ignored.("B"))
      assert {:ok, [%Patch{selector: "#rocket"}]} = Template.diff(rocket.("A"), rocket.("B"))
      assert {:ok, [%Patch{selector: "#owned"}]} = Template.diff(owned.("A"), owned.("B"))
    end
  end

  test "Patch.opts/1 returns StarView.Elements.patch/3 options" do
    assert Patch.opts(%Patch{selector: "#a", elements: "<p id=\"a\"></p>"}) ==
             [selector: "#a", mode: :outer, namespace: :html]
  end

  defp template(nodes, fingerprint \\ "fp"),
    do: %Template{fingerprint: fingerprint, nodes: List.wrap(nodes)}

  defp assert_invalid_attributes(attrs) do
    assert_raise ArgumentError, fn -> html(el("div", attrs, [])) end
  end

  defp html(nodes), do: nodes |> template() |> Template.to_html()

  defp el(tag, attrs, children), do: Node.element(tag, attrs, children)
  defp value(value), do: Node.value(value)
  defp id(value), do: {:static, "id", value, "\""}

  defp badge(title) do
    assigns = %{title: title}
    ~H'<span class="badge">{@title}</span>'
  end

  defp assert_legacy_rejected(position) do
    nodes = legacy_position(position, badge("Legacy"))
    assert_raise ArgumentError, ~r/legacy HEEx.*incompatible/, fn -> html(nodes) end
  end

  defp legacy_position(:body, legacy), do: value(legacy)
  defp legacy_position(:list, legacy), do: value(["Before", [legacy]])
  defp legacy_position(:attribute, legacy), do: el("p", [{:dynamic, "title", legacy}], [])
  defp legacy_position(:spread, legacy), do: el("p", [{:spread, [title: [legacy]]}], [])
  defp legacy_position(:class, legacy), do: el("p", [{:dynamic, "class", ["one", [legacy]]}], [])

  defp list(a, b) do
    template(
      el("ul", [id("list")], [el("li", [id("a")], [value(a)]), el("li", [id("b")], [value(b)])])
    )
  end

  defp classes(addressable, anonymous) do
    first = el("li", [id("a"), {:dynamic, "class", addressable}], [Node.text("A")])
    second = el("li", [{:dynamic, "class", anonymous}], [Node.text("B")])
    template(el("ul", [id("list")], [first, second]))
  end

  defp panel(shown), do: template(el("section", [id("panel")], [panel_branch(shown)]))

  defp panel_branch(:yes), do: Node.branch(true, [el("p", [id("yes")], [Node.text("Yes")])])
  defp panel_branch(:no), do: Node.branch(false, [el("p", [id("no")], [Node.text("No")])])
  defp panel_branch(:none), do: Node.branch(false, [])

  defp rows(entries),
    do: template(el("tbody", [id("rows")], [Node.keyed(Enum.map(entries, &row/1))]))

  defp row({key, label}),
    do: Node.fragment([el("tr", [id("row-#{key}")], [el("td", [], [value(label)])])], key)

  defp wrapped(child_attrs, label),
    do: template(el("div", [id("wrap")], [el("p", child_attrs, [value(label)])]))

  defp duplicates(label) do
    template(
      el("div", [id("wrap")], [el("p", [id("dup")], [value(label)]), el("p", [id("dup")], [])])
    )
  end

  defp outer(class, label) do
    template(
      el("div", [id("outer"), {:dynamic, "class", class}], [
        el("p", [id("inner")], [value(label)])
      ])
    )
  end

  defp card(fingerprint, label) do
    body = template(el("p", [id("body")], [value(label)]), fingerprint)
    template(el("article", [id("card")], [Node.component(body)]))
  end

  defp chart(radius) do
    circle = Node.element("circle", [id("dot"), {:dynamic, "r", radius}], [], %{namespace: :svg})
    svg = Node.element("svg", [id("svg")], [circle], %{namespace: :svg})
    template(el("div", [id("chart")], [el("figure", [], [svg])]))
  end

  defp host(child), do: template(el("div", [id("host")], [child]))
  defp inner(label), do: el("p", [id("inner")], [value(label)])
end
