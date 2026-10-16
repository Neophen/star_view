defmodule StarView.TemplateProgramCompilerTest do
  use ExUnit.Case, async: false

  import StarView.Template.Sigils

  alias StarView.Template

  test "compiled rendering and its materialized tree agree across attribute and branch values" do
    Enum.each(
      [nil, false, true, "", [], [nil, false], [[], nil], "<&\"", ["a", nil, [false, "b"]]],
      &assert_oracle/1
    )
  end

  test "expressions run once in source order and never while rendering or diffing" do
    Process.put(:star_program_calls, [])
    template = ordered(%{rows: ["a", "b"]})
    expected = [:id, :key, :condition, "a", :key, :condition, "b", :tail]
    assert Enum.reverse(Process.get(:star_program_calls)) == expected
    assert Template.to_html(template) == tree_html(template)
    assert {:ok, []} = Template.diff(template, template)
    assert Enum.reverse(Process.get(:star_program_calls)) == expected
  end

  test "generated rendering functions capture evaluated values only in the data tuple" do
    template = oracle(%{value: "private value", visible: true})
    assert {:env, []} = :erlang.fun_info(template.program.run, :env)
    refute inspect(template.program.run) =~ "private value"
    assert Template.to_html(template) == tree_html(template)
  end

  test "an expression exception stops subsequent expressions" do
    Process.put(:star_program_calls, [])
    assert_raise RuntimeError, "stop", fn -> interrupted(%{}) end
    assert Process.get(:star_program_calls) == [:first]
  end

  test "module programs survive unchanged recompiles without retaining old code" do
    options = Code.compiler_options(ignore_module_conflict: true)
    on_exit(fn -> Code.compiler_options(options) end)
    module = StarView.TemplateProgramCompilerTest.Reloaded
    Code.compile_string(reload_source("original"))
    old = apply(module, :page, [%{value: "dynamic"}])
    assert {:type, :external} = :erlang.fun_info(old.program.run, :type)

    Code.compile_string(reload_source("original"))
    assert :code.soft_purge(module)
    assert Template.to_html(old) == "<p>originaldynamic</p>"

    Code.compile_string(reload_source("changed"))
    assert :code.soft_purge(module)
    next = apply(module, :page, [%{value: "dynamic"}])
    assert_raise StarView.Template.StaleProgramError, fn -> Template.to_html(old) end

    assert {:reset, :template_changed} =
             Template.diff(old, %{next | fingerprint: old.fingerprint})

    Code.compile_string(reload_source("third"))
    assert :code.soft_purge(module)
    assert Template.to_html(apply(module, :page, [%{value: "dynamic"}])) == "<p>thirddynamic</p>"
  end

  defp reload_source(text) do
    """
    defmodule StarView.TemplateProgramCompilerTest.Reloaded do
      import StarView.Template.Sigils
      def page(assigns), do: ~STAR"<p>#{text}{@value}</p>"
    end
    """
  end

  test "function-local aliases remain bound in evaluated keys" do
    template = local_key(%{rows: ["a"]})
    [root] = Template.nodes(template)
    keyed = Enum.find(root.children, &(&1.kind == :keyed))
    assert [item] = keyed.children
    assert item.key == StarView.Template
  end

  test "evaluation with an already-compiled module environment uses an immediate program" do
    template = evaluate(%{value: "<&>"})
    assert Template.to_html(template) == "<p>&lt;&amp;&gt;</p>"
    assert {:type, :local} = :erlang.fun_info(template.program.run, :type)
  end

  defp evaluate(assigns) do
    {template, _bindings} =
      Code.eval_string(~S|~STAR"<p>{@value}</p>"|, [assigns: assigns], __ENV__)

    template
  end

  defp local_key(assigns) do
    alias StarView.Template, as: Key

    ~STAR"<ul>
  <li :for={row <- @rows} :key={Key}>{row}</li>
</ul>"
  end

  test "component and slot attributes evaluate in source order" do
    StarView.TemplateProgramCompilerTest.OrderedSlots.page(%{})
    assert next_slot_value() == :attribute
    assert next_slot_value() == :zeta
    assert next_slot_value() == :alpha
    refute_received {:slot_value, _}
  end

  test "binary interpolation and concatenation keep escaping and the tree equivalent" do
    Enum.each(["", "<>&\"'", "plain"], &assert_binary_attributes/1)
  end

  test "binary operands evaluate before type validation but later content does not" do
    Process.put(:star_program_calls, [])
    assert_raise ArgumentError, fn -> invalid_binary(%{left: 123}) end
    assert Process.get(:star_program_calls) == [:right]
  end

  defp invalid_binary(assigns) do
    ~STAR"""
    <div title={@left <> record(:right, "right")}>{record(:body, "body")}</div>
    """
  end

  test "tampered binary parts cannot insert safe HTML into an attribute" do
    template = binary_attributes(%{value: "value", suffix: "suffix"})
    values = put_elem(template.program.values, 0, {:safe, "\" onclick=evil"})
    template = %{template | program: %{template.program | values: values}}
    assert_raise ArgumentError, fn -> Template.to_html(template) end
    assert_raise ArgumentError, fn -> Template.nodes(template) end
  end

  defp assert_binary_attributes(value) do
    template = binary_attributes(%{value: value, suffix: "tail"})
    assert Template.to_html(template) == tree_html(template)
    assert Template.to_html(template) =~ "&lt;static&gt;"
    refute Template.to_html(template) =~ ~s(title="<static>)
  end

  defp binary_attributes(assigns) do
    ~STAR"""
    <div title={"<static>#{@value} & fixed #{ @suffix }"} data-test={"before" <> @value <> "after"}>
    </div>
    """
  end

  test "invalid spread names are validated on the compiled render path" do
    template = spread(%{rest: [{"onclick x", "value"}]})
    assert_raise ArgumentError, ~r/invalid attribute name/, fn -> Template.to_html(template) end
    assert_raise ArgumentError, ~r/invalid attribute name/, fn -> tree_html(template) end
  end

  defp next_slot_value() do
    receive do
      {:slot_value, label} -> label
    after
      0 -> flunk("missing slot value")
    end
  end

  defp assert_oracle(value) do
    template = oracle(%{value: value, visible: true})
    assert Template.to_html(template) == tree_html(template)
    assert Template.to_html(oracle(%{value: value, visible: false})) =~ "hidden"
  end

  defp tree_html(%Template{} = template),
    do: Template.to_html(%{template | program: nil, nodes: Template.nodes(template)})

  defp oracle(assigns) do
    ~STAR"""
    <section id="root" title="A &amp; B" class={["<static>", "base", @value, "tail"]} style={false}>
      <input checked={@value == true} data={[label: inspect(@value)]} />
      <%= if @visible do %>
        <b>{inspect(@value)}</b>
      <% else %>
        <i>hidden</i>
      <% end %>
    </section>
    """
  end

  defp ordered(assigns) do
    ~STAR"""
    <section id={record(:id, "root")}>
      <b :for={row <- @rows} :if={record(:condition, true)} :key={record(:key, row)}>{record(row, row)}</b>
      {record(:tail, "done")}
    </section>
    """
  end

  defp interrupted(assigns) do
    ~STAR"""
    <div title={record(:first, "value")}>{raise "stop"}{record(:last, "unreachable")}</div>
    """
  end

  defp spread(assigns), do: ~STAR"<div {@rest}>value</div>"

  defp record(label, value) do
    Process.put(:star_program_calls, [label | Process.get(:star_program_calls)])
    value
  end
end
