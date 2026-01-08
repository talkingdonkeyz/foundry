# Detect available toolchains
cargo_available? = Foundry.Test.IntegrationHelpers.cargo_available?()
cmake_available? = Foundry.Test.IntegrationHelpers.cmake_available?()

IO.puts("Toolchain detection:")
IO.puts("  Cargo: #{if cargo_available?, do: "available", else: "not found"}")
IO.puts("  CMake: #{if cmake_available?, do: "available", else: "not found"}")

# Build exclusion list based on what's not available
excludes =
  []
  |> then(fn list -> if cargo_available?, do: list, else: [:requires_cargo | list] end)
  |> then(fn list -> if cmake_available?, do: list, else: [:requires_cmake | list] end)

if excludes != [] do
  IO.puts("Excluding tests tagged: #{inspect(excludes)}")
end

ExUnit.start(exclude: excludes)
