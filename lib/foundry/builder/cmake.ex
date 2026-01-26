defmodule Foundry.Builder.CMake do
  @moduledoc """
  CMake (C/C++) builder implementation.

  ## Builder Options

  - `:target` - CMake target name to build (defaults to first binary name)
  - `:args` - Extra CMake arguments (e.g., `["-DENABLE_FEATURE=ON"]`)
  - `:build_dir` - Custom CMake build directory (default: `_build/<env>/native/<app>/build`)
  """

  @behaviour Foundry.Builder

  @impl true
  @spec default_source_path() :: String.t()
  def default_source_path, do: "c_src"

  @impl true
  @spec validate_opts!(keyword()) :: :ok | no_return()
  def validate_opts!(opts) do
    target = Keyword.get(opts, :target)
    args = Keyword.get(opts, :args, [])
    build_dir = Keyword.get(opts, :build_dir)

    validate_target!(target)
    validate_args!(args)
    validate_build_dir!(build_dir)

    :ok
  end

  defp validate_target!(nil), do: :ok
  defp validate_target!(target) when is_binary(target), do: :ok

  defp validate_target!(other) do
    Mix.raise("Invalid :target option: #{inspect(other)}. Expected a string")
  end

  defp validate_args!(args) when is_list(args), do: :ok

  defp validate_args!(other) do
    Mix.raise("Invalid :args option: #{inspect(other)}. Expected a list of strings")
  end

  defp validate_build_dir!(nil), do: :ok
  defp validate_build_dir!(dir) when is_binary(dir), do: :ok

  defp validate_build_dir!(other) do
    Mix.raise("Invalid :build_dir option: #{inspect(other)}. Expected a string")
  end

  @impl true
  @spec build!(String.t(), String.t(), keyword()) :: :ok | no_return()
  def build!(source_path, profile, opts) do
    binaries = Keyword.fetch!(opts, :binaries)
    target = Keyword.get(opts, :target) || List.first(binaries)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])
    otp_app = Keyword.fetch!(opts, :otp_app)

    build_dir = resolve_build_dir(opts, otp_app)
    File.mkdir_p!(build_dir)

    cmake_configure!(source_path, build_dir, profile, args, env)
    cmake_build!(build_dir, target, profile, env)
  end

  @impl true
  @spec binary_paths(String.t(), [String.t()], String.t(), keyword()) :: %{
          String.t() => String.t()
        }
  def binary_paths(_source_path, binaries, _profile, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    build_dir = resolve_build_dir(opts, otp_app)
    extension = exe_extension()

    Map.new(binaries, fn name ->
      binary_name = name <> extension
      path = find_cmake_output(build_dir, binary_name) || Path.join(build_dir, binary_name)
      {name, path}
    end)
  end

  @impl true
  @spec discover_resources(String.t()) :: [String.t()]
  def discover_resources(source_path) do
    cmake_files =
      [
        Path.join(source_path, "CMakeLists.txt"),
        Path.join(source_path, "CMakePresets.json")
      ]
      |> Enum.filter(&File.exists?/1)

    source_files =
      source_path
      |> Path.join("src/**/*.{c,cc,cpp,cxx,h,hpp}")
      |> Path.wildcard()

    test_files =
      source_path
      |> Path.join("test/**/*.{c,cc,cpp,cxx,h,hpp}")
      |> Path.wildcard()

    cmake_files ++ source_files ++ test_files
  end

  @impl true
  @spec supports_test?() :: boolean()
  def supports_test?, do: true

  @impl true
  @spec test!(String.t(), keyword()) :: Foundry.Builder.test_result()
  def test!(source_path, opts) do
    env = Keyword.get(opts, :env, [])
    otp_app = Keyword.fetch!(opts, :otp_app)
    test_args = Keyword.get(opts, :test_args, [])
    cmake_test_args = Keyword.get(opts, :cmake_test_args, [])

    # Use a separate build directory for tests
    test_build_dir = resolve_test_build_dir(opts, otp_app)
    File.mkdir_p!(test_build_dir)

    # Configure with BUILD_TESTING=ON
    configure_result = cmake_test_configure!(source_path, test_build_dir, cmake_test_args, env)

    case configure_result do
      {:error, output, status} ->
        %{status: :error, exit_code: status, output: output}

      :ok ->
        # Build the test target
        build_result = cmake_test_build!(test_build_dir, env)

        case build_result do
          {:error, output, status} ->
            %{status: :error, exit_code: status, output: output}

          :ok ->
            # Run ctest
            run_ctest!(test_build_dir, test_args, env)
        end
    end
  end

  defp cmake_test_configure!(source_path, build_dir, extra_args, env) do
    args =
      [
        "-S", source_path,
        "-B", build_dir,
        "-DBUILD_TESTING=ON"
      ] ++ Enum.map(extra_args, &to_string/1)

    Mix.shell().info("Running cmake #{Enum.join(args, " ")}")

    case System.cmd("cmake", args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, output, status}
    end
  end

  defp cmake_test_build!(build_dir, env) do
    args = ["--build", build_dir]

    Mix.shell().info("Running cmake #{Enum.join(args, " ")}")

    case System.cmd("cmake", args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, output, status}
    end
  end

  defp run_ctest!(build_dir, test_args, env) do
    # Find test subdirectory if it exists
    test_dir =
      if File.dir?(Path.join(build_dir, "test")) do
        Path.join(build_dir, "test")
      else
        build_dir
      end

    args =
      ["--test-dir", test_dir, "--output-on-failure"]
      |> Kernel.++(test_args)

    Mix.shell().info("Running ctest #{Enum.join(args, " ")}")

    case System.cmd("ctest", args, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        %{status: :ok, exit_code: 0, output: output}

      {output, status} ->
        %{status: :error, exit_code: status, output: output}
    end
  end

  defp resolve_test_build_dir(opts, otp_app) do
    Keyword.get(opts, :test_build_dir) || default_test_build_dir(otp_app)
  end

  defp default_test_build_dir(otp_app) do
    Path.join([
      Mix.Project.build_path(),
      "native",
      to_string(otp_app),
      "build_test"
    ])
  end

  # Private helpers

  defp cmake_configure!(source_path, build_dir, profile, extra_args, env) do
    build_type = if profile == "release", do: "Release", else: "Debug"

    args =
      [
        "-S",
        source_path,
        "-B",
        build_dir,
        "-DCMAKE_BUILD_TYPE=#{build_type}"
      ] ++ Enum.map(extra_args, &to_string/1)

    run_cmd!("cmake", args, env)
  end

  defp cmake_build!(build_dir, target, profile, env) do
    args =
      ["--build", build_dir, "--target", target]
      |> maybe_append(profile == "release", ["--config", "Release"])

    run_cmd!("cmake", args, env)
  end

  defp default_build_dir(otp_app) do
    Path.join([
      Mix.Project.build_path(),
      "native",
      to_string(otp_app),
      "build"
    ])
  end

  defp resolve_build_dir(opts, otp_app) do
    Keyword.get(opts, :build_dir) || default_build_dir(otp_app)
  end

  defp find_cmake_output(build_dir, binary_name) do
    [
      Path.join(build_dir, binary_name),
      Path.join([build_dir, "Release", binary_name]),
      Path.join([build_dir, "Debug", binary_name])
    ]
    |> Enum.find(&File.regular?/1)
  end

  defp run_cmd!(cmd, args, env) do
    Mix.shell().info("Running #{cmd} #{Enum.join(args, " ")}")

    case System.cmd(cmd, args, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        if output != "", do: IO.binwrite(output)
        :ok

      {output, status} ->
        Mix.raise("#{cmd} #{Enum.join(args, " ")} failed with status #{status}\n#{output}")
    end
  end

  defp exe_extension do
    case :os.type() do
      {:win32, _} -> ".exe"
      _ -> ""
    end
  end

  defp maybe_append(list, false, _extra), do: list
  defp maybe_append(list, true, extra), do: list ++ extra
end
