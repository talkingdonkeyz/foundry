defmodule Foundry.Builder.CMake do
  @moduledoc """
  CMake (C/C++) builder implementation.

  ## Builder Options

  - `:target` - CMake target name to build (defaults to first binary name)
  - `:args` - Extra CMake arguments (e.g., `["-DENABLE_FEATURE=ON"]`)
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

    validate_target!(target)
    validate_args!(args)

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

  @impl true
  @spec build!(String.t(), String.t(), keyword()) :: :ok | no_return()
  def build!(source_path, profile, opts) do
    binaries = Keyword.fetch!(opts, :binaries)
    target = Keyword.get(opts, :target) || List.first(binaries)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])
    otp_app = Keyword.fetch!(opts, :otp_app)

    build_dir = cmake_build_dir(otp_app)
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
    build_dir = cmake_build_dir(otp_app)
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

    cmake_files ++ source_files
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

  defp cmake_build_dir(otp_app) do
    Path.join([
      Mix.Project.build_path(),
      "native",
      to_string(otp_app),
      "build"
    ])
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
