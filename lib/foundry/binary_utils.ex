defmodule Foundry.BinaryUtils do
  @moduledoc false

  @doc """
  Copies binaries from their source paths to priv/.
  Returns list of destination paths.
  """
  @spec copy_binaries!(%{String.t() => String.t()}, String.t()) :: [String.t()]
  def copy_binaries!(binary_paths, priv_dir) do
    Enum.map(binary_paths, fn {name, src} ->
      dest = Path.join(priv_dir, Path.basename(src))
      copy_binary(src, dest, name)
      dest
    end)
  end

  defp copy_binary(src, dest, name) do
    if File.regular?(src) do
      File.cp!(src, dest)
      maybe_chmod_exec(dest)
      Mix.shell().info("Copied #{src} -> #{dest}")
    else
      Mix.shell().info("Binary #{name} not found at #{src}, skipping")
    end
  end

  defp maybe_chmod_exec(path) do
    case :os.type() do
      {:win32, _} -> :ok
      _ -> File.chmod!(path, 0o755)
    end
  end
end
