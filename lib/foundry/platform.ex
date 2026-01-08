defmodule Foundry.Platform do
  @moduledoc """
  Platform detection utilities for Foundry.

  Provides functions to detect the current OS and architecture,
  and check if the current platform matches specified constraints.
  """

  @type os :: :linux | :macos | :windows | :freebsd | :unknown
  @type arch :: :x86_64 | :arm64 | :arm | :unknown

  @doc """
  Returns the current operating system as a normalized atom.

  ## Examples

      iex> Foundry.Platform.current_os()
      :linux
  """
  @spec current_os() :: os()
  def current_os do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:unix, :freebsd} -> :freebsd
      {:win32, _} -> :windows
      _ -> :unknown
    end
  end

  @doc """
  Returns the current CPU architecture as a normalized atom.

  ## Examples

      iex> Foundry.Platform.current_arch()
      :x86_64
  """
  @spec current_arch() :: arch()
  def current_arch do
    arch_string =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.downcase()

    cond do
      String.contains?(arch_string, "x86_64") or String.contains?(arch_string, "amd64") ->
        :x86_64

      String.contains?(arch_string, "aarch64") or String.contains?(arch_string, "arm64") ->
        :arm64

      String.contains?(arch_string, "arm") ->
        :arm

      true ->
        :unknown
    end
  end

  @doc """
  Checks if the current platform matches the given OS and architecture constraints.

  Returns `true` if:
  - Both `os` and `arch` are `nil` (no constraints)
  - The current OS is in the `os` list (or `os` is `nil`)
  - The current architecture is in the `arch` list (or `arch` is `nil`)

  ## Examples

      # No constraints - always matches
      iex> Foundry.Platform.matches?(nil, nil)
      true

      # OS constraint only
      iex> Foundry.Platform.matches?([:linux, :macos], nil)
      true  # if on Linux or macOS

      # Both constraints
      iex> Foundry.Platform.matches?([:linux], [:x86_64])
      true  # if on Linux x86_64
  """
  @spec matches?(os_list :: [os()] | nil, arch_list :: [arch()] | nil) :: boolean()
  def matches?(nil, nil), do: true

  def matches?(os_list, arch_list) do
    os_matches? = is_nil(os_list) or current_os() in os_list
    arch_matches? = is_nil(arch_list) or current_arch() in arch_list
    os_matches? and arch_matches?
  end

  @doc """
  Returns a human-readable description of the current platform.

  ## Examples

      iex> Foundry.Platform.description()
      "linux/x86_64"
  """
  @spec description() :: String.t()
  def description do
    "#{current_os()}/#{current_arch()}"
  end

  @doc """
  Returns a human-readable description of required platform constraints.

  ## Examples

      iex> Foundry.Platform.constraints_description([:linux], [:x86_64])
      "linux/x86_64"

      iex> Foundry.Platform.constraints_description([:linux, :macos], nil)
      "linux,macos/any"
  """
  @spec constraints_description(os_list :: [os()] | nil, arch_list :: [arch()] | nil) ::
          String.t()
  def constraints_description(os_list, arch_list) do
    os_str = if os_list, do: Enum.join(os_list, ","), else: "any"
    arch_str = if arch_list, do: Enum.join(arch_list, ","), else: "any"
    "#{os_str}/#{arch_str}"
  end
end
