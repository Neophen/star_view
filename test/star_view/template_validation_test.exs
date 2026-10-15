defmodule StarView.TemplateValidationTest do
  use ExUnit.Case, async: true

  alias StarView.Template
  alias StarView.Template.HTML
  alias StarView.Template.Node
  alias StarView.Template.Renderer

  @attribute_name ~r/\A[^\s"'<>\/=`&\x00-\x1F\x7F]+\z/u
  @tag_name ~r/\A[A-Za-z][A-Za-z0-9_.:-]*\z/

  test "ASCII fast paths preserve validation for every byte in each position" do
    Enum.each(0..127, &assert_ascii_byte/1)
  end

  test "Unicode names and invalid UTF8 preserve the existing attribute contract" do
    names = [
      "",
      "café",
      "属性",
      "data-😀",
      "x\u00a0y",
      "x\u2028y",
      "x\u3000y",
      <<255>>,
      "x" <> <<192, 128>>
    ]

    Enum.each(names, &assert_attribute_name/1)
  end

  test "optimized binary and boolean attributes retain Phoenix escaping" do
    values = [
      nil,
      false,
      true,
      "",
      "<>&\"'",
      "Café 😀",
      <<0, 1, 127>>,
      <<255>>,
      {:safe, "&amp;"},
      123
    ]

    Enum.each(values, &assert_attribute_value/1)
  end

  test "nested dynamic and spread names still reject forged attributes" do
    attrs = [
      {:dynamic, "data", [{"id onclick", "x"}]},
      {:dynamic, "aria", [{"label=bad", "x"}]},
      {:spread, [data: [{"x>y", "x"}]]},
      {:spread, [{"x onload", false}]}
    ]

    Enum.each(attrs, &assert_invalid_attribute/1)
  end

  defp assert_ascii_byte(byte) do
    names = [<<byte>>, "data-" <> <<byte>>, <<byte>> <> "name", "na" <> <<byte>> <> "me"]
    Enum.each(names, &assert_attribute_name/1)
    Enum.each(names, &assert_tag_name/1)
  end

  test "numeric ids retain Phoenix validation through dynamic and spread attributes" do
    Enum.each([{:dynamic, "id", 123}, {:spread, [id: 123]}], &assert_invalid_numeric_id/1)
  end

  test "spread class and nested safe values preserve Phoenix behavior" do
    spreads = [
      [class: ["a", nil, false, "b"]],
      [class: nil],
      [class: true],
      [data: [x: {:safe, "&amp;"}]]
    ]

    Enum.each(spreads, &assert_spread_value/1)
  end

  defp assert_invalid_numeric_id(attribute) do
    template = %Template{nodes: [Node.element("p", [attribute])]}
    assert_raise ArgumentError, fn -> Template.to_html(template) end
  end

  defp assert_spread_value(attrs) do
    template = %Template{nodes: [Node.element("p", [{:spread, attrs}])]}
    expected = attrs |> Phoenix.HTML.attributes_escape() |> Phoenix.HTML.safe_to_string()
    assert Template.to_html(template) == "<p" <> expected <> "></p>"
  end

  defp assert_attribute_name(name) do
    assert accepts?(fn -> HTML.attribute_name!(name) end) ==
             accepts?(fn -> regex_attribute!(name) end)
  end

  defp regex_attribute!(name) do
    if !Regex.match?(@attribute_name, name), do: raise(ArgumentError)
  end

  defp assert_tag_name(name) do
    assert accepts?(fn -> Renderer.tag!(name) end) == Regex.match?(@tag_name, name)
  end

  defp accepts?(fun) do
    fun.()
    true
  rescue
    ArgumentError -> false
  end

  defp assert_attribute_value(value) do
    attrs = [{:dynamic, "title", value}]
    template = %Template{nodes: [Node.element("p", attrs)]}
    expected = Phoenix.HTML.attributes_escape(title: value) |> Phoenix.HTML.safe_to_string()
    assert Template.to_html(template) == "<p" <> expected <> "></p>"
  end

  defp assert_invalid_attribute(attribute) do
    template = %Template{nodes: [Node.element("p", [attribute])]}
    assert_raise ArgumentError, ~r/invalid attribute name/, fn -> Template.to_html(template) end
  end
end
