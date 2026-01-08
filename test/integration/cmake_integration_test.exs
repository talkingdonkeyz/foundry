defmodule Foundry.Integration.CMakeTest do
  use ExUnit.Case, async: false

  alias Foundry.Test.IntegrationHelpers

  @moduletag :requires_cmake

  setup do
    test_id = IntegrationHelpers.unique_test_id()

    on_exit(fn ->
      IntegrationHelpers.cleanup_build(test_id)
      cleanup_priv()
    end)

    {:ok, test_id: test_id}
  end

  describe "cmake builder" do
    test "builds and copies binary to priv", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cmake,
          binaries: ["cmake_hello"],
          source_path: fixture_path,
          builder_opts: [build_dir: build_dir(test_id)]
        )

      assert config.platform_supported? == true
      assert "cmake_hello" in config.binaries

      # Verify binary was copied to priv
      priv_path = priv_binary_path("cmake_hello")
      assert File.exists?(priv_path), "Binary should exist at #{priv_path}"
    end

    test "binary is executable and produces correct output", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)

      Foundry.Compiler.compile(:foundry, [],
        otp_app: :foundry,
        builder: :cmake,
        binaries: ["cmake_hello"],
        source_path: fixture_path,
        builder_opts: [build_dir: build_dir(test_id)]
      )

      priv_path = priv_binary_path("cmake_hello")

      {output, exit_code} = System.cmd(priv_path, [], stderr_to_stdout: true)

      assert exit_code == 0
      assert String.trim(output) == "hello from cmake"
    end

    test "registers external resources for recompilation", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cmake,
          binaries: ["cmake_hello"],
          source_path: fixture_path,
          builder_opts: [build_dir: build_dir(test_id)]
        )

      # Should have registered CMakeLists.txt and .c files
      assert Enum.any?(config.external_resources, &String.ends_with?(&1, "CMakeLists.txt"))
      assert Enum.any?(config.external_resources, &String.ends_with?(&1, ".c"))
    end

    test "recompiles when source file changes", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)
      build_dir = build_dir(test_id)

      # Initial compile
      Foundry.Compiler.compile(:foundry, [],
        otp_app: :foundry,
        builder: :cmake,
        binaries: ["cmake_hello"],
        source_path: fixture_path,
        builder_opts: [build_dir: build_dir]
      )

      priv_path = priv_binary_path("cmake_hello")

      # Verify initial output
      {initial_output, 0} = System.cmd(priv_path, [], stderr_to_stdout: true)
      assert String.trim(initial_output) == "hello from cmake"

      # Modify source file
      main_c = Path.join([fixture_path, "src", "main.c"])

      File.write!(main_c, """
      #include <stdio.h>

      int main(void) {
          printf("hello from cmake modified\\n");
          return 0;
      }
      """)

      # Touch with future timestamp to ensure build system sees the change
      File.touch!(main_c, System.os_time(:second) + 2)

      # Recompile
      Foundry.Compiler.compile(:foundry, [],
        otp_app: :foundry,
        builder: :cmake,
        binaries: ["cmake_hello"],
        source_path: fixture_path,
        builder_opts: [build_dir: build_dir]
      )

      # Verify output changed (proves rebuild happened)
      {new_output, 0} = System.cmd(priv_path, [], stderr_to_stdout: true)
      assert String.trim(new_output) == "hello from cmake modified"
    end

    test "supports release profile", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)

      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cmake,
          binaries: ["cmake_hello"],
          source_path: fixture_path,
          profile: "release",
          builder_opts: [build_dir: build_dir(test_id)]
        )

      assert config.profile == "release"

      priv_path = priv_binary_path("cmake_hello")
      assert File.exists?(priv_path)

      {output, 0} = System.cmd(priv_path, [], stderr_to_stdout: true)
      assert String.trim(output) == "hello from cmake"
    end

    test "supports custom cmake arguments", %{test_id: test_id} do
      fixture_path = IntegrationHelpers.setup_fixture("cmake_hello", test_id)

      # This just verifies that passing args doesn't break the build
      config =
        Foundry.Compiler.compile(:foundry, [],
          otp_app: :foundry,
          builder: :cmake,
          binaries: ["cmake_hello"],
          source_path: fixture_path,
          builder_opts: [build_dir: build_dir(test_id), args: ["-DCMAKE_VERBOSE_MAKEFILE=ON"]]
        )

      assert config.platform_supported? == true

      priv_path = priv_binary_path("cmake_hello")
      assert File.exists?(priv_path)
    end
  end

  # Helpers

  defp build_dir(test_id) do
    Path.join([System.tmp_dir!(), "foundry_test", test_id, "build"])
  end

  defp priv_binary_path(name) do
    extension = if match?({:win32, _}, :os.type()), do: ".exe", else: ""
    Path.join([Mix.Project.app_path(), "priv", name <> extension])
  end

  defp cleanup_priv do
    priv_dir = Path.join(Mix.Project.app_path(), "priv")

    if File.dir?(priv_dir) do
      priv_dir
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "cmake_hello"))
      |> Enum.each(fn file ->
        File.rm(Path.join(priv_dir, file))
      end)
    end
  end
end
