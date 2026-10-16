defmodule StarView.MixProject do
  use Mix.Project

  @version "0.7.0"

  def project() do
    [
      app: :star_view,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir SDK for Datastar SSE events with Plug and Phoenix helpers.",
      package: package(),
      docs: docs(),
      source_url: "https://github.com/Neophen/star_view",
      homepage_url: "https://hexdocs.pm/star_view"
    ]
  end

  def application() do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.14"},
      {:igniter, "~> 0.8.4", optional: true},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      name: "star_view",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Neophen/star_view",
        "Datastar" => "https://data-star.dev"
      },
      files:
        ~w(assets lib priv guides skills mix.exs README.md CHANGELOG.md LICENSE usage-rules.md .formatter.exs)
    ]
  end

  defp docs() do
    [
      main: "overview",
      api_reference: false,
      logo: "assets/logo.png",
      extra_section: "GUIDES",
      source_ref: "v#{@version}",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras() do
    [
      "guides/introduction/overview.md",
      "guides/introduction/mental_model.md",
      "guides/introduction/installation.md",
      "guides/introduction/agent_skill.md",
      "guides/phoenix/web_module.md",
      "guides/phoenix/layout.md",
      "guides/phoenix/auth.md",
      "guides/phoenix/pages.md",
      "guides/phoenix/development_server.md",
      "guides/phoenix/compression.md",
      "guides/core/patch_signals.md",
      "guides/core/actions.md",
      "guides/core/checked_events.md",
      "guides/core/patch_element.md",
      "guides/core/stream_deduplication.md",
      "guides/core/csrf.md",
      "guides/comparison/liveview_vs_star_view.md",
      "guides/examples/phoenix_counter.md",
      "guides/examples/plug_endpoints.md",
      "guides/examples/pubsub_stream.md",
      "guides/examples/reactive_rendering.md",
      "guides/examples/star_templates.md",
      "guides/reference/api_overview.md",
      "guides/reference/migration_from_dstar.md",
      "guides/reference/troubleshooting.md",
      {"CHANGELOG.md", title: "Changelog"}
    ]
  end

  defp groups_for_extras() do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Phoenix: ~r/guides\/phoenix\/.?/,
      "Core Concepts": ~r/guides\/core\/.?/,
      Comparison: ~r/guides\/comparison\/.?/,
      Examples: ~r/guides\/examples\/.?/,
      Reference: ~r/guides\/reference\/.?/,
      "Release Notes": ~r/CHANGELOG/
    ]
  end

  defp groups_for_modules() do
    [
      "Experimental templates": [
        StarView.Template,
        StarView.Template.Node,
        StarView.Template.Patch,
        StarView.Template.Sigils,
        StarView.Template.Formatter
      ],
      Core: [
        StarView.Events,
        StarView,
        StarView.SSE,
        StarView.Elements,
        StarView.Signals,
        StarView.Scripts,
        StarView.Actions,
        StarView.JSON,
        StarView.Stream,
        StarView.StreamRegistry
      ],
      Plugs: [
        StarView.Plug.Dispatch,
        StarView.Plug.RenameCsrfParam
      ],
      Phoenix: [
        StarView.Controller,
        StarView.Dispatch,
        StarView.Page,
        StarView.Page.Assigns,
        StarView.Page.Helpers,
        StarView.Page.Plug,
        StarView.Component,
        StarView.Router
      ],
      Testing: [StarView.Test]
    ]
  end
end
