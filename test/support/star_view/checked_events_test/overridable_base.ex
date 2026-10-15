defmodule StarView.CheckedEventsTest.OverridableBase do
  @moduledoc false

  # Injects an overridable handler, like a shared base module would.
  defmacro __using__(_opts) do
    quote do
      def handle_event("old", _signals, %{method: "POST"} = conn) do
        send(self(), {:checked_event, __MODULE__, :old})
        conn
      end

      defoverridable handle_event: 3
    end
  end
end
