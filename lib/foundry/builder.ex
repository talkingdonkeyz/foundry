defmodule Foundry.Builder do
  @moduledoc """
  Behaviour for native build systems.

  Foundry ships with two built-in builders:
  - `:cargo` - Rust projects via Cargo
  - `:cmake` - C/C++ projects via CMake

  Custom builders can be used by passing a module that implements this behaviour.
  """

  @type source_path :: String.t()
  @type binaries :: [String.t()]
  @type profile :: String.t()
  @type opts :: keyword()

  @type test_result :: %{
          status: :ok | :error,
          exit_code: non_neg_integer(),
          output: String.t()
        }

  @doc "Returns the default source directory (e.g., \"native\" for Cargo)"
  @callback default_source_path() :: String.t()

  @doc "Validates builder-specific options, raises on invalid config"
  @callback validate_opts!(opts()) :: :ok | no_return()

  @doc "Runs the native build process"
  @callback build!(source_path(), profile(), opts()) :: :ok | no_return()

  @doc "Returns a map of binary names to their built output paths"
  @callback binary_paths(source_path(), binaries(), profile(), opts()) :: %{
              String.t() => String.t()
            }

  @doc "Returns list of source files to watch for recompilation"
  @callback discover_resources(source_path()) :: [String.t()]

  @doc """
  Runs native tests. Returns a test result map with status, exit code, and output.

  This callback is optional. Builders that don't support testing should not implement it.
  """
  @callback test!(source_path(), opts()) :: test_result()

  @doc """
  Returns true if the builder supports native testing.

  Default implementation returns false. Override in builders that support testing.
  """
  @callback supports_test?() :: boolean()

  @optional_callbacks [test!: 2, supports_test?: 0]

  @doc "Resolves builder to module. Built-in shortcuts `:cargo` and `:cmake` are expanded."
  @spec get!(atom()) :: module()
  def get!(:cargo), do: Foundry.Builder.Cargo
  def get!(:cmake), do: Foundry.Builder.CMake
  def get!(module) when is_atom(module), do: module

  @doc "Checks if a builder module supports testing"
  @spec supports_test?(module()) :: boolean()
  def supports_test?(builder_mod) do
    function_exported?(builder_mod, :supports_test?, 0) and builder_mod.supports_test?()
  end

  @doc "Runs tests for a builder if supported"
  @spec run_test(module(), source_path(), opts()) :: {:ok, test_result()} | {:error, :not_supported}
  def run_test(builder_mod, source_path, opts) do
    if supports_test?(builder_mod) do
      {:ok, builder_mod.test!(source_path, opts)}
    else
      {:error, :not_supported}
    end
  end
end
