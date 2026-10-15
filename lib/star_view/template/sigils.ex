defmodule StarView.Template.Sigils do
  @moduledoc """
  The experimental `~STAR` sigil compiles HEEx syntax into a StarView-owned tree.

  Import this module alongside `Phoenix.Component`. The parser adapter currently
  supports Phoenix LiveView 1.2.12; existing StarView APIs keep their own requirements.
  """

  defmacro sigil_STAR({:<<>>, meta, [source]}, modifiers)
           when is_binary(source) and modifiers in [[], ~c"noformat"] do
    StarView.Template.Compiler.compile(source, __CALLER__, meta)
  end
end
