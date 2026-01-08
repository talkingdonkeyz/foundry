defmodule Foundry.Test.IntegrationHelpers do
  @moduledoc """
  Helper functions for integration tests.
  """

  @fixtures_path Path.expand("../fixtures", __DIR__)

  @doc """
  Returns the path to a fixture directory.
  """
  @spec fixture_path(String.t()) :: String.t()
  def fixture_path(name) do
    Path.join(@fixtures_path, name)
  end

  @doc """
  Copies a fixture to a temporary directory for isolated testing.
  Returns the path to the copied fixture.
  """
  @spec setup_fixture(String.t(), String.t()) :: String.t()
  def setup_fixture(fixture_name, test_id) do
    source = fixture_path(fixture_name)
    dest = Path.join([System.tmp_dir!(), "foundry_test", test_id, fixture_name])

    File.rm_rf!(dest)
    File.mkdir_p!(Path.dirname(dest))
    File.cp_r!(source, dest)

    dest
  end

  @doc """
  Cleans up build artifacts for a test.
  """
  @spec cleanup_build(String.t()) :: :ok
  def cleanup_build(test_id) do
    build_path = Path.join([System.tmp_dir!(), "foundry_test", test_id])
    File.rm_rf!(build_path)
    :ok
  end

  @doc """
  Creates a unique test ID for isolation.
  """
  @spec unique_test_id() :: String.t()
  def unique_test_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @doc """
  Checks if cargo is available on the system.
  """
  @spec cargo_available?() :: boolean()
  def cargo_available? do
    case System.cmd("cargo", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Checks if cmake is available on the system.
  """
  @spec cmake_available?() :: boolean()
  def cmake_available? do
    case System.cmd("cmake", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Touches a file to trigger recompilation.
  """
  @spec touch_file(String.t()) :: :ok
  def touch_file(path) do
    # Ensure mtime changes by waiting a moment and using File.touch
    Process.sleep(1000)
    File.touch!(path)
    :ok
  end

  @doc """
  Returns a non-matching OS constraint for platform tests.
  """
  @spec non_matching_os() :: [atom()]
  def non_matching_os do
    case Foundry.Platform.current_os() do
      :linux -> [:windows]
      :macos -> [:windows]
      :windows -> [:linux]
      _ -> [:windows]
    end
  end
end
