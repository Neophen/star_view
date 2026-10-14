defmodule Mix.Tasks.StarView.Setup.StreamPage.Docs do
  @moduledoc false

  def short_doc(), do: "Generates an SSE streaming demo page driven by Phoenix.PubSub"
  def example(), do: "mix star_view.setup.stream_page"

  def long_doc() do
    """
    #{short_doc()}

    Generates a working end-to-end streaming example:

    * `MyAppWeb.StreamDemoPage` — a `StarView.Page` at `/stream-demo` that
      opens an SSE stream on load (`connect()`), subscribes to PubSub in
      `handle_connect/2`, and patches signals from `handle_info/2`.
    * `MyApp.DemoTicker` — a GenServer added to your supervision tree that
      broadcasts the server time over Phoenix.PubSub every second.
    * Router wiring — `import StarView.Router` plus
      `star_view "/stream-demo", StreamDemoPage`.

    ## Example

    ```sh
    #{example()}
    ```

    Then start the server and open `/stream-demo` — the page updates every
    second without polling or custom JavaScript. Both generated modules are
    demo code: delete them freely.
    """
  end
end
