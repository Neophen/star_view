defmodule StarView.CheckedEventsTest.DeleteHandler do
  @moduledoc false

  # Simulates a later before_compile hook that removes the handler the
  # checked event contract was derived from.
  defmacro __before_compile__(env) do
    Module.delete_definition(env.module, {:handle_event, 3})
    nil
  end
end
