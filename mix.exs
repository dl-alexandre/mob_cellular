defmodule Mob.Cellular.MixProject do
  use Mix.Project

  @github_url "https://github.com/dl-alexandre/mob_cellular"
  @version "0.2.0"
  @description "Cellular fallback transport plugin for mob using push notification envelopes."

  def project do
    [
      app: :mob_cellular,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      # Coverage is reported in the umbrella summary but not gated here; this
      # plugin is published independently (threshold 0 => summary only, never fails).
      test_coverage: [summary: [threshold: 0]],
      deps: deps(),
      aliases: aliases(),
      description: @description,
      package: package(),
      source_url: @github_url,
      homepage_url: @github_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "docs/CARRIER_DECISION.md",
          "docs/COST_AND_BATTERY.md",
          "docs/HARDWARE_VALIDATION.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ]
    ]
  end

  def application do
    [
      mod: {MobCellular.Application, []},
      extra_applications: [:logger, :telemetry]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test]
    ]
  end

  defp deps do
    transport_dep() ++
      [
        {:telemetry, "~> 1.3"},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:ex_doc, "~> 0.40.2", only: :dev, runtime: false}
      ]
  end

  # Resolve the shared Mob.Transport contract from the sibling app when developed
  # inside the umbrella; omit it entirely from the published package (the
  # behaviour is applied optionally via Code.ensure_loaded?/1).
  defp transport_dep do
    if File.exists?(Path.expand("../mob_transport/mix.exs", __DIR__)),
      do: [{:mob_transport, in_umbrella: true}],
      else: []
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Changelog" => "#{@github_url}/blob/main/CHANGELOG.md",
        "mob" => "https://github.com/GenericJam/mob",
        "mob_dev" => "https://github.com/GenericJam/mob_dev"
      },
      files: ~w(
        lib
        priv/mob_plugin.exs
        scripts
        docs
        mix.exs
        README.md
        CONTRIBUTING.md
        CHANGELOG.md
        LICENSE
      )
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "test",
        "credo --strict"
      ]
    ]
  end
end
