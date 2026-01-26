defmodule Foundry.Builder.Cargo do
  @moduledoc """
  Cargo (Rust) builder implementation.

  ## Builder Options

  - `:cargo` - Cargo binary to use. Either `:system` (default) or `{:bin, "/path/to/cargo"}`
  - `:target` - Rust target triple for cross-compilation (e.g., `"aarch64-unknown-linux-gnu"`)
  - `:target_dir` - Custom Cargo target directory (default: `_build/<env>/native/<app>/target`)
  """

  @behaviour Foundry.Builder

  @type cargo_option :: :system | {:bin, String.t()}

  @impl true
  @spec default_source_path() :: String.t()
  def default_source_path, do: "native"

  @impl true
  @spec validate_opts!(keyword()) :: :ok | no_return()
  def validate_opts!(opts) do
    cargo = Keyword.get(opts, :cargo, :system)
    target = Keyword.get(opts, :target)
    target_dir = Keyword.get(opts, :target_dir)

    validate_cargo!(cargo)
    validate_target!(target)
    validate_target_dir!(target_dir)

    :ok
  end

  defp validate_cargo!(:system), do: :ok
  defp validate_cargo!({:bin, path}) when is_binary(path), do: :ok

  defp validate_cargo!(other) do
    Mix.raise("Invalid :cargo option: #{inspect(other)}. Expected :system or {:bin, path}")
  end

  defp validate_target!(nil), do: :ok
  defp validate_target!(target) when is_binary(target), do: :ok

  defp validate_target!(other) do
    Mix.raise("Invalid :target option: #{inspect(other)}. Expected a string")
  end

  defp validate_target_dir!(nil), do: :ok
  defp validate_target_dir!(dir) when is_binary(dir), do: :ok

  defp validate_target_dir!(other) do
    Mix.raise("Invalid :target_dir option: #{inspect(other)}. Expected a string")
  end

  @impl true
  @spec build!(String.t(), String.t(), keyword()) :: :ok | no_return()
  def build!(source_path, profile, opts) do
    cargo = Keyword.get(opts, :cargo, :system)
    target = Keyword.get(opts, :target)
    env = Keyword.get(opts, :env, [])
    otp_app = Keyword.fetch!(opts, :otp_app)
    target_dir = resolve_target_dir(opts, otp_app)

    args =
      ["build"]
      |> maybe_append(profile == "release", ["--release"])
      |> maybe_append(not is_nil(target), ["--target", target])

    cmd = cargo_bin(cargo)
    cmd_env = cargo_env(target_dir, env)

    Mix.shell().info("Running #{cmd} #{Enum.join(args, " ")} in #{source_path}")

    case System.cmd(cmd, args, cd: source_path, env: cmd_env, stderr_to_stdout: true) do
      {output, 0} ->
        if output != "", do: IO.binwrite(output)
        :ok

      {output, status} ->
        Mix.raise("#{cmd} #{Enum.join(args, " ")} failed with status #{status}\n#{output}")
    end
  end

  @impl true
  @spec binary_paths(String.t(), [String.t()], String.t(), keyword()) :: %{
          String.t() => String.t()
        }
  def binary_paths(_source_path, binaries, profile, opts) do
    target = Keyword.get(opts, :target)
    otp_app = Keyword.fetch!(opts, :otp_app)
    target_dir = resolve_target_dir(opts, otp_app)

    profile_dir = if profile == "release", do: "release", else: "debug"

    bin_dir =
      if target do
        Path.join([target_dir, target, profile_dir])
      else
        Path.join([target_dir, profile_dir])
      end

    extension = exe_extension()

    Map.new(binaries, fn name ->
      {name, Path.join(bin_dir, name <> extension)}
    end)
  end

  @impl true
  @spec discover_resources(String.t()) :: [String.t()]
  def discover_resources(source_path) do
    cargo_files =
      [
        Path.join(source_path, "Cargo.toml"),
        Path.join(source_path, "Cargo.lock")
      ]
      |> Enum.filter(&File.exists?/1)

    member_cargo =
      source_path
      |> Path.join("**/Cargo.toml")
      |> Path.wildcard()
      |> Enum.filter(&File.exists?/1)

    rust_sources =
      source_path
      |> Path.join("**/*.rs")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/target/"))

    cargo_files ++ member_cargo ++ rust_sources
  end

  @impl true
  @spec supports_test?() :: boolean()
  def supports_test?, do: true

  @impl true
  @spec test!(String.t(), keyword()) :: Foundry.Builder.test_result()
  def test!(source_path, opts) do
    cargo = Keyword.get(opts, :cargo, :system)
    target = Keyword.get(opts, :target)
    env = Keyword.get(opts, :env, [])
    otp_app = Keyword.fetch!(opts, :otp_app)
    target_dir = resolve_target_dir(opts, otp_app)
    test_args = Keyword.get(opts, :test_args, [])

    args =
      ["test"]
      |> maybe_append(not is_nil(target), ["--target", target])
      |> Kernel.++(test_args)

    cmd = cargo_bin(cargo)
    cmd_env = cargo_env(target_dir, env)

    Mix.shell().info("Running #{cmd} #{Enum.join(args, " ")} in #{source_path}")

    case System.cmd(cmd, args, cd: source_path, env: cmd_env, stderr_to_stdout: true) do
      {output, 0} ->
        %{status: :ok, exit_code: 0, output: output}

      {output, status} ->
        %{status: :error, exit_code: status, output: output}
    end
  end

  # Private helpers

  defp cargo_bin(:system), do: "cargo"
  defp cargo_bin({:bin, path}) when is_binary(path), do: path

  defp cargo_build_dir(otp_app) do
    Path.join([Mix.Project.build_path(), "native", to_string(otp_app), "target"])
  end

  defp resolve_target_dir(opts, otp_app) do
    Keyword.get(opts, :target_dir) || cargo_build_dir(otp_app)
  end

  defp cargo_env(target_dir, extra) do
    [{"CARGO_TARGET_DIR", target_dir} | extra]
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
