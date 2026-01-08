defmodule Foundry.UnsupportedPlatformError do
  @moduledoc """
  Raised when attempting to access a native binary on an unsupported platform.

  This error is raised at runtime when code tries to get the path to a binary
  that was not compiled because the current platform doesn't match the
  configured `:os` and `:arch` constraints.
  """

  defexception [:binary, :required_os, :required_arch]

  @impl true
  def message(%__MODULE__{} = error) do
    current = Foundry.Platform.description()
    required = Foundry.Platform.constraints_description(error.required_os, error.required_arch)

    "Binary '#{error.binary}' is not available on this platform. " <>
      "Required: #{required}. Current: #{current}."
  end
end
