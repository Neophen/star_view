defmodule StarView.TemplateDiffRegressionTest do
  use ExUnit.Case, async: true

  alias StarView.Template
  alias StarView.Template.Node

  test "nested and sibling patches retain document order" do
    assert {:ok, patches} = Template.diff(document("Before"), document("After"))
    assert Enum.map(patches, & &1.selector) == ["#first", "#nested", "#last"]
    assert Enum.all?(patches, &String.contains?(&1.elements, "After"))
  end

  test "invalid selector ids bubble to the existing valid ancestor" do
    Enum.each(["1a", "-a", "a.b", "a:b", "é", "", "a b"], &assert_bubbles/1)
  end

  test "missing keys precede duplicates in the same snapshot" do
    assert Template.diff(keyed([nil, 1, 1]), keyed([1])) == {:reset, :missing_key}
  end

  test "invalid previous keys precede invalid next keys" do
    assert Template.diff(keyed([1, 1]), keyed([nil, 1])) == {:reset, {:duplicate_key, 1}}
  end

  defp document(text) do
    nodes = [
      element("first", text),
      Node.element("div", [], [element("nested", text)]),
      element("last", text)
    ]

    %Template{fingerprint: "order", nodes: [Node.element("main", [], nodes)]}
  end

  defp element(id, text), do: Node.element("p", [{:dynamic, "id", id}], [Node.value(text)])

  defp assert_bubbles(id) do
    assert {:ok, [patch]} = Template.diff(wrapped(id, "Before"), wrapped(id, "After"))
    assert patch.selector == "#wrapper"
  end

  defp wrapped(id, text) do
    %Template{
      fingerprint: "ids",
      nodes: [Node.element("div", [{:dynamic, "id", "wrapper"}], [element(id, text)])]
    }
  end

  defp keyed(keys) do
    fragments = Enum.map(keys, &Node.fragment([Node.text(inspect(&1))], &1))
    %Template{fingerprint: "keys", nodes: [Node.keyed(fragments)]}
  end
end
