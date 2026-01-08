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

  @doc "Resolves builder to module. Built-in shortcuts `:cargo` and `:cmake` are expanded."
  @spec get!(atom()) :: module()
  def get!(:cargo), do: Foundry.Builder.Cargo
  def get!(:cmake), do: Foundry.Builder.CMake
  def get!(module) when is_atom(module), do: module
end
