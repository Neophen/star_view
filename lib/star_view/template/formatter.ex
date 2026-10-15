if Code.ensure_loaded?(Phoenix.LiveView.HTMLFormatter) do
  defmodule StarView.Template.Formatter do
    @moduledoc "Mix formatter plugin for the experimental `~STAR` sigil."

    def features(_opts), do: [sigils: [:STAR], extensions: []]

    def format(contents, opts) do
      if opts[:modifiers] == ~c"noformat",
        do: contents,
        else: Phoenix.LiveView.HTMLFormatter.format(contents, opts)
    end
  end
end
