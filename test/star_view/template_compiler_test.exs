defmodule StarView.TemplateCompilerTest do
  use ExUnit.Case, async: true

  alias StarView.Template
  alias StarView.Template.Node
  alias StarView.Template.Patch
  alias StarView.TemplateTest.Components
  alias StarView.TemplateTest.Legacy

  test "STAR returns our tree and keeps literal markup separate from bindings" do
    template = Components.counter(%{count: 1, title: "Title"})

    assert %Template{nodes: [%Node{kind: :element, tag: "main", children: children} | _]} =
             template

    counter = Enum.find(children, &(&1.tag == "p"))
    assert %Node{children: [%Node{kind: :value, value: 1, meta: meta}]} = counter
    assert meta.dependencies == [:count]
    assert is_binary(template.fingerprint)
    assert Template.to_html(template) =~ ~s(<p id="counter">1</p>)
  end

  test "one changed assign produces one complete HTML patch" do
    previous = Components.counter(%{count: 1, title: "Title"})
    next = Components.counter(%{count: 2, title: "Title"})
    assert {:ok, [patch]} = Template.diff(previous, next)
    assert patch.selector == "#counter"
    assert patch.elements == ~s(<p id="counter">2</p>)
    assert {:ok, []} = Template.diff(next, next)
  end

  test "planned HTML patches use the existing Datastar SSE transport" do
    previous = Components.counter(%{count: 1, title: "Title"})
    next = Components.counter(%{count: 2, title: "Title"})
    {:ok, patches} = Template.diff(previous, next)
    conn = Plug.Test.conn(:post, "/") |> StarView.start()
    result = Enum.reduce(patches, conn, &send_patch/2)
    StarView.Test.assert_patched_element(result, "#counter")
    [event] = StarView.Test.sse_events(result)
    assert event.type == "datastar-patch-elements"
    assert "elements <p id=\"counter\">2</p>" in event.data
  end

  test "branch switches replace an existing ancestor rather than a missing new target" do
    previous = Components.conditional(%{shown: true, name: "Name"})
    next = Components.conditional(%{shown: false, name: "Name"})
    assert {:ok, [patch]} = Template.diff(previous, next)
    assert patch.selector == "#content"
    assert patch.elements =~ ~s(<p id="no">Hidden</p>)
    refute patch.elements =~ ~s(id="yes")
  end

  test "components and named let slots keep native STAR content" do
    template = Components.page(%{title: "Card", name: "Name"})
    html = Template.to_html(template)
    assert html =~ "<h2>Card</h2>"
    assert html =~ ~s(<p id="greeting">Name</p>)
    assert html =~ "<button>Action</button>"
  end

  test "legacy HEEx components fail with a conversion error" do
    assert_raise ArgumentError, ~r/legacy HEEx.*incompatible.*Convert/, fn ->
      Components.mixed(%{title: "<hello>"})
    end
  end

  test "native component slots select a changed descendant" do
    previous = Components.page(%{title: "Card", name: "Alice"})
    next = Components.page(%{title: "Card", name: "Bob"})
    assert {:ok, [patch]} = Template.diff(previous, next)
    assert patch.selector == "#greeting"
    assert patch.elements == ~s(<p id="greeting">Bob</p>)
  end

  test "a STAR component renders multiple native slots" do
    html = %{} |> Components.multiple_slots() |> Template.to_html()
    assert html =~ ~s(<section id="columns">OneTwo</section>)
  end

  test "dynamic content and attribute escaping agrees with Phoenix" do
    Enum.each([nil, false, "two", ["two", nil, "three"]], &assert_matches_heex/1)
  end

  test "dynamic attributes and content escape while literal entities remain literal" do
    assigns = %{disabled: true, class: "two", rest: %{data_id: "x"}, value: ~s(<script>"&)}
    html = assigns |> Components.escaped() |> Template.to_html()
    assert html =~ ~s(title="A &amp; B")
    assert html =~ ~s(class="one two")
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
    refute html =~ "&amp;amp;"
    refute html =~ "</input>"
  end

  test "for and if directives retain keys and conditional branches" do
    items = [%{id: "a", title: "A", visible: true}, %{id: "b", title: "B", visible: false}]
    template = Components.directives(%{items: items})
    [%Node{children: children} | _] = template.nodes
    keyed = Enum.find(children, &(&1.kind == :keyed))
    assert Enum.map(keyed.children, & &1.key) == ["a", "b"]
    html = Template.to_html(template)
    assert html =~ ~s(id="item-a")
    refute html =~ ~s(id="item-b")
    assert {:ok, []} = Template.diff(template, Components.directives(%{items: items}))
  end

  test "duplicate list keys fail before choosing patch targets" do
    item = %{id: "a", title: "A", visible: true}

    assert_raise ArgumentError, ~r/unique/, fn ->
      Components.directives(%{items: [item, item]})
    end
  end

  test "plain for blocks render as conservative fragments" do
    html = %{items: [%{title: "A"}, %{title: "B"}]} |> Components.raw_for() |> Template.to_html()
    assert html =~ ~r/<li>A<\/li>\s*<li>B<\/li>/
  end

  test "missing assigns fail with a bounded error" do
    assert_raise ArgumentError, "missing @count assign in ~STAR template", fn ->
      Components.counter(%{})
    end
  end

  test "nil list keys fail before choosing patch targets" do
    item = %{id: nil, title: "A", visible: true}

    assert_raise ArgumentError, ~r/must not be nil/, fn ->
      Components.directives(%{items: [item]})
    end
  end

  test "unsupported constructs fail during compilation" do
    examples = [
      {:With, "<%= with true <- @value do %>yes<% end %>"},
      {:Statement, "<% value = @value %>{value}"},
      {:Macro, "<div :type={Some.Macro}>hello</div>"},
      {:RepeatedSlot,
       "<.card title=\"Card\"><:actions :for={item <- @items}>{item}</:actions></.card>"},
      {:Key, "<p :key={@value}>hello</p>"}
    ]

    Enum.each(examples, &assert_unsupported/1)
  end

  test "inline legacy sigils fail at compilation with a conversion error" do
    assert_raise CompileError, ~r/legacy HEEx.*incompatible/, fn ->
      compile_template(:LegacySigil, ~S|<p>{~H"legacy"}</p>|)
    end
  end

  test "legacy static slot content is rejected" do
    legacy = Legacy.badge(%{title: "Legacy"})

    assert_raise ArgumentError, ~r/~STAR slot.*incompatible/, fn ->
      StarView.Template.Runtime.render_slot(%{inner_block: legacy})
    end
  end

  test "legacy slot callbacks are rejected" do
    entry = %{inner_block: &legacy_slot/2}

    assert_raise ArgumentError, ~r/~STAR slot.*incompatible/, fn ->
      StarView.Template.Runtime.render_slot(entry)
    end
  end

  defp legacy_slot(_changed, _argument), do: Legacy.badge(%{title: "Legacy"})

  test "Phoenix still validates malformed HTML" do
    assert_raise Phoenix.LiveView.TagEngine.Tokenizer.ParseError, fn ->
      compile_template(:Malformed, "<div><p>hello</div>")
    end
  end

  test "Phoenix retains required component attribute diagnostics" do
    ExUnit.CaptureIO.capture_io(:stderr, &assert_required_attribute_diagnostic/0)
  end

  defp assert_required_attribute_diagnostic() do
    {_result, diagnostics} =
      Code.with_diagnostics([log: false], fn -> compile_template(:RequiredAttr, "<.card />") end)

    assert Enum.any?(diagnostics, &String.contains?(&1.message, "missing required attribute"))
  end

  test "the formatter handles STAR contents and respects noformat" do
    source = ~s(~STAR"""\n<div>\n <p>Hello</p>\n    <p>World</p>\n</div>\n""")
    formatted = format(source)
    assert formatted =~ "~STAR"
    assert formatted =~ "  <p>Hello</p>\n  <p>World</p>"
    assert format(source <> "noformat") == source <> "noformat"
  end

  defp format(source),
    do:
      source
      |> Code.format_string!(sigils: [STAR: &StarView.Template.Formatter.format/2])
      |> IO.iodata_to_binary()

  defp assert_matches_heex(class) do
    assigns = %{
      disabled: true,
      class: class,
      rest: %{data: [user_id: "<&"]},
      value: ~s(<script>"&)
    }

    own = assigns |> Components.escaped() |> Template.to_html()
    legacy = assigns |> Legacy.escaped() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    assert normalize_classes(own) == normalize_classes(legacy)
  end

  # HEEx extracts static class prefixes and can retain a trailing separator.
  # STAR deliberately joins the evaluated class list without empty entries.
  defp normalize_classes(html), do: Regex.replace(~r/class="([^"]*)"/, html, &normalized_class/2)

  defp normalized_class(_attribute, classes),
    do: "class=\"" <> (classes |> String.split() |> Enum.join(" ")) <> "\""

  defp assert_unsupported({name, source}) do
    assert_raise CompileError, ~r/~STAR:/, fn -> compile_template(name, source) end
  end

  defp compile_template(name, source) do
    module = Module.concat(__MODULE__, name)

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Phoenix.Component
      import StarView.Template.Sigils
      import StarView.TemplateTest.Components, only: [card: 1]
      def render(assigns) do
        ~STAR\"\"\"
        #{source}
        \"\"\"
      end
    end
    """)
  end

  defp send_patch(patch, conn),
    do: StarView.patch_elements(conn, patch.elements, Patch.opts(patch))
end
