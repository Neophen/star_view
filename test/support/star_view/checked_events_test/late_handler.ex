defmodule StarView.CheckedEventsTest.LateHandler do
  @moduledoc false

  # Simulates another library whose before_compile hook adds a handler clause
  # after the checked event contract was generated.
  defmacro __before_compile__(_env) do
    quote do
      def handle_event("late", _signals, %{method: "POST"} = conn), do: conn
    end
  end
end
