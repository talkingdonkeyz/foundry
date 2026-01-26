defmodule Mix.Tasks.Foundry.Test do
  @shortdoc "Run native tests for Foundry modules"
  @moduledoc """
  Runs native tests for all Foundry modules in the project.

  ## Usage

      mix foundry.test [options]

  ## Options

    * `--only MODULE` - Only run tests for the specified module (e.g., `MyApp.Native`)
    * `--verbose` - Print full test output even on success
    * `--` - Pass remaining arguments to the underlying test runner

  ## Examples

      # Run all native tests
      mix foundry.test

      # Run tests for a specific module
      mix foundry.test --only MyApp.Native

      # Pass arguments to cargo test
      mix foundry.test -- --nocapture

      # Pass arguments to ctest
      mix foundry.test -- -R "pattern"
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, test_args, _} =
      OptionParser.parse(args,
        strict: [only: :string, verbose: :boolean],
        aliases: [o: :only, v: :verbose]
      )

    # Ensure project is compiled first
    Mix.Task.run("compile", [])

    modules = discover_foundry_modules()

    modules =
      case Keyword.get(opts, :only) do
        nil -> modules
        only -> Enum.filter(modules, fn {mod, _} -> to_string(mod) =~ only end)
      end

    if Enum.empty?(modules) do
      Mix.shell().info("No Foundry modules found with test support")
    else
      results =
        Enum.map(modules, fn {module, config} ->
          run_tests(module, config, test_args, opts)
        end)

      # Summary
      passed = Enum.count(results, fn {_, r} -> r.status == :ok end)
      failed = Enum.count(results, fn {_, r} -> r.status == :error end)
      skipped = Enum.count(results, fn {_, r} -> r.status == :skipped end)

      Mix.shell().info("")
      Mix.shell().info("Native tests: #{passed} passed, #{failed} failed, #{skipped} skipped")

      if failed > 0 do
        Mix.raise("Native tests failed")
      end
    end
  end

  defp discover_foundry_modules do
    # Load all application modules first
    load_all_application_modules()

    # Get all modules that use Foundry
    for {mod, _beam_file} <- :code.all_loaded(),
        Code.ensure_loaded?(mod),
        function_exported?(mod, :__foundry_config__, 0) do
      {mod, mod.__foundry_config__()}
    end
  end

  defp load_all_application_modules do
    # Get all apps in the project (umbrella support)
    apps = Mix.Project.apps_paths() || %{Mix.Project.config()[:app] => "."}

    Enum.each(apps, fn {app, _path} ->
      # Ensure the application is loaded
      Application.load(app)

      # Get the application's beam directory
      app_path = Mix.Project.build_path() |> Path.join("lib/#{app}/ebin")

      if File.dir?(app_path) do
        # Load all beam files
        app_path
        |> Path.join("*.beam")
        |> Path.wildcard()
        |> Enum.each(fn beam_file ->
          module =
            beam_file
            |> Path.basename(".beam")
            |> String.to_atom()

          Code.ensure_loaded(module)
        end)
      end
    end)
  end

  defp run_tests(module, config, test_args, opts) do
    Mix.shell().info("")
    Mix.shell().info("Running native tests for #{inspect(module)}...")

    builder_mod = Foundry.Builder.get!(config.builder)

    if Foundry.Builder.supports_test?(builder_mod) do
      builder_opts =
        config.builder_opts
        |> Keyword.put(:otp_app, config.otp_app)
        |> Keyword.put(:binaries, config.binaries)
        |> Keyword.put(:env, config.env)
        |> Keyword.put(:test_args, test_args)

      result = builder_mod.test!(config.source_path, builder_opts)

      if opts[:verbose] or result.status == :error do
        Mix.shell().info(result.output)
      end

      case result.status do
        :ok ->
          Mix.shell().info("#{inspect(module)}: PASSED")

        :error ->
          Mix.shell().error("#{inspect(module)}: FAILED (exit code #{result.exit_code})")
      end

      {module, result}
    else
      Mix.shell().info("#{inspect(module)}: skipped (builder does not support testing)")
      {module, %{status: :skipped, exit_code: 0, output: ""}}
    end
  end
end
