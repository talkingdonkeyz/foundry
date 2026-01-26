defmodule Foundry.Integration.NativeTestTest do
  use ExUnit.Case, async: false

  alias Foundry.Builder.{Cargo, CMake}

  @moduletag :integration

  describe "Cargo.test!/2" do
    test "runs cargo test and returns success for passing tests" do
      result = Cargo.test!(
        "test/fixtures/rust_hello",
        otp_app: :foundry_test,
        binaries: ["rust_hello"]
      )

      assert result.status == :ok
      assert result.exit_code == 0
      assert result.output =~ "test result: ok"
      assert result.output =~ "2 passed"
    end

    test "returns test_args to cargo test" do
      result = Cargo.test!(
        "test/fixtures/rust_hello",
        otp_app: :foundry_test,
        binaries: ["rust_hello"],
        test_args: ["--", "--nocapture"]
      )

      assert result.status == :ok
      # With --nocapture, we should see the test output
      assert result.output =~ "running 2 tests"
    end
  end

  describe "CMake.test!/2" do
    test "runs ctest and returns success for passing tests" do
      result = CMake.test!(
        "test/fixtures/cmake_hello",
        otp_app: :foundry_test,
        binaries: ["cmake_hello"]
      )

      assert result.status == :ok
      assert result.exit_code == 0
      assert result.output =~ "100% tests passed"
    end
  end

  describe "Builder.supports_test?/1" do
    test "returns true for Cargo builder" do
      assert Foundry.Builder.supports_test?(Cargo) == true
    end

    test "returns true for CMake builder" do
      assert Foundry.Builder.supports_test?(CMake) == true
    end

    test "returns false for unknown builder" do
      defmodule NoTestBuilder do
        @behaviour Foundry.Builder
        def default_source_path, do: "src"
        def validate_opts!(_), do: :ok
        def build!(_, _, _), do: :ok
        def binary_paths(_, bins, _, _), do: Map.new(bins, &{&1, &1})
        def discover_resources(_), do: []
      end

      assert Foundry.Builder.supports_test?(NoTestBuilder) == false
    end
  end
end
