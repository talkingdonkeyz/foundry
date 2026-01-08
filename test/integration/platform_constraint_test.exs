defmodule Foundry.Integration.PlatformConstraintTest do
  use ExUnit.Case, async: true

  alias Foundry.Test.IntegrationHelpers

  describe "platform constraints" do
    test "skips compilation when OS constraint doesn't match" do
      # Use an OS that doesn't match the current one
      non_matching_os = IntegrationHelpers.non_matching_os()

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cargo,
          binaries: ["fake_binary"],
          source_path: "/nonexistent/path",
          os: non_matching_os
        )

      assert config.platform_supported? == false
      assert config.external_resources == []
      assert config.os == non_matching_os
    end

    test "skips compilation when arch constraint doesn't match" do
      # Use an arch that doesn't match the current one
      non_matching_arch =
        case Foundry.Platform.current_arch() do
          :x86_64 -> [:arm64]
          :arm64 -> [:x86_64]
          :arm -> [:x86_64]
          _ -> [:arm64]
        end

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cargo,
          binaries: ["fake_binary"],
          source_path: "/nonexistent/path",
          arch: non_matching_arch
        )

      assert config.platform_supported? == false
      assert config.external_resources == []
      assert config.arch == non_matching_arch
    end

    test "compiles when constraints match current platform" do
      current_os = Foundry.Platform.current_os()
      current_arch = Foundry.Platform.current_arch()

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cargo,
          binaries: ["fake_binary"],
          source_path: "/nonexistent/path",
          os: [current_os],
          arch: [current_arch],
          skip_compilation?: true
        )

      # Platform is supported (even though build won't find source)
      assert config.platform_supported? == true
    end

    test "compiles when no constraints specified" do
      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cargo,
          binaries: ["fake_binary"],
          source_path: "/nonexistent/path",
          skip_compilation?: true
        )

      assert config.platform_supported? == true
      assert config.os == nil
      assert config.arch == nil
    end
  end

  describe "Foundry.Platform" do
    test "current_os returns a known atom" do
      os = Foundry.Platform.current_os()
      assert os in [:linux, :macos, :windows, :freebsd, :unknown]
    end

    test "current_arch returns a known atom" do
      arch = Foundry.Platform.current_arch()
      assert arch in [:x86_64, :arm64, :arm, :unknown]
    end

    test "matches?/2 returns true when no constraints" do
      assert Foundry.Platform.matches?(nil, nil) == true
    end

    test "matches?/2 checks OS when specified" do
      current_os = Foundry.Platform.current_os()
      assert Foundry.Platform.matches?([current_os], nil) == true
      assert Foundry.Platform.matches?([:nonexistent_os], nil) == false
    end

    test "matches?/2 checks arch when specified" do
      current_arch = Foundry.Platform.current_arch()
      assert Foundry.Platform.matches?(nil, [current_arch]) == true
      assert Foundry.Platform.matches?(nil, [:nonexistent_arch]) == false
    end

    test "description returns os/arch string" do
      desc = Foundry.Platform.description()
      assert desc =~ ~r/^[a-z]+\/[a-z0-9_]+$/
    end
  end

  describe "UnsupportedPlatformError" do
    test "can be raised with binary and constraints" do
      error = %Foundry.UnsupportedPlatformError{
        binary: "my_binary",
        required_os: [:linux],
        required_arch: [:x86_64]
      }

      message = Exception.message(error)
      assert message =~ "my_binary"
      assert message =~ "linux"
      assert message =~ "x86_64"
    end
  end
end
