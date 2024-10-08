defmodule Wyz.MixProject do
  use Mix.Project

  def project do
    [
      app: :wyz,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Documentation
      name: "Wyz",
      source_url: "https://github.com/myrrlyn/v4.myrrlyn.net",
      homepage_url: "https://myrrlyn.net/elixir/wyz",
      docs: [
        main: "Wyz",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true}
      {:earmark, "~> 1.4"},
      {:earmark_parser, "~> 1.4"},
      {:floki, "~> 0.36"},
      {:ok, "~> 2.3"},
      {:yaml_elixir, "~> 2.11"},
      {:timex, "~> 3.7"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
