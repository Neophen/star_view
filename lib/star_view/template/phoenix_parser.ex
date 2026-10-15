defmodule StarView.Template.PhoenixParser do
  @moduledoc false

  @tested_version "1.2.12"
  @parser Phoenix.LiveView.TagEngine.Parser
  @engine Phoenix.LiveView.TagEngine

  def parse!(source, caller, meta) do
    ensure_version!()
    opts = options(caller, meta)
    parsed = apply(@parser, :parse!, [source, Keyword.put(opts, :skip_macro_components, true)])
    parsed.nodes
  end

  # Run the ordinary compiler for HTML validation and component-call metadata.
  # Its generated Rendered AST is discarded; our lowering emits the actual tree.
  def validate!(source, caller, meta) do
    apply(@engine, :compile, [source, options(caller, meta)])
    :ok
  end

  defp ensure_version!() do
    ensure_available!()
    _ = Application.load(:phoenix_live_view)
    version = :phoenix_live_view |> Application.spec(:vsn) |> to_string()
    check_version!(version)
  end

  defp ensure_available!() do
    if !Code.ensure_loaded?(@parser) do
      raise ArgumentError, "~STAR requires the optional Phoenix LiveView dependency"
    end
  end

  defp check_version!(@tested_version), do: :ok

  defp check_version!(version) do
    raise ArgumentError,
          "the experimental ~STAR parser adapter requires Phoenix LiveView #{@tested_version}, got #{version}; other StarView APIs are unaffected"
  end

  defp options(caller, meta) do
    [
      caller: caller,
      file: caller.file,
      line: caller.line + 1,
      indentation: meta[:indentation] || 0,
      tag_handler: Phoenix.LiveView.HTMLEngine
    ]
  end
end
