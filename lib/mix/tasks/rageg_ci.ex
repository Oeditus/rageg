defmodule Mix.Tasks.Rageg.Ci do
  @shortdoc "Run diff-based quality gateway analysis for CI (rageg + metacredo)"

  @moduledoc """
  Runs diff-based quality gateway checks for CI pipelines (GitHub Actions, GitLab CI, etc.).

  Sequentially executes:
  1. `mix metacredo --diff` (AST and security quality checks)
  2. `mix quality.ci` (formatting and Credo strict analysis)

  ## Usage

      mix rageg.ci [options]

  ## Options

    * `--base REF` - Base git ref (default: origin/main)
    * `--head REF` - Head git ref (default: HEAD)
    * `--format FORMAT` - Output format: text, github (default: text)
    * `--config PATH` - Path to `.metacredo.exs` config file for metacredo

  ## Examples

      # Run in GitHub Actions PR workflow
      mix rageg.ci --base origin/$GITHUB_BASE_REF --format github
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          base: :string,
          head: :string,
          format: :string,
          config: :string
        ]
      )

    base = opts[:base]
    head = opts[:head]
    format = opts[:format] || "text"
    config = opts[:config]

    metacredo_args =
      ["--diff", "--strict", "--format", format] ++
        if(base, do: ["--base", base], else: []) ++
        if(head, do: ["--head", head], else: []) ++
        if(config, do: ["--config", config], else: [])

    Mix.Task.run("metacredo", metacredo_args)
    Mix.Task.run("quality.ci", [])
  end
end
