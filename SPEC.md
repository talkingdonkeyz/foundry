<!--
 Copyright (c) 2025 Zach Webb <zacharyjwebb@gmail.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Foundry Specification

**Status:** Implemented
**Version:** 1.1
**Last Updated:** 2026-01-26

---

## 1. Overview

### 1.1 Purpose

Foundry is a compile-time build tool for Elixir that integrates native executables (Rust, C/C++) into the Mix compilation pipeline. Native binaries are built during `mix compile`, copied to `priv/`, and exposed through generated path helper functions.

The design philosophy: **Native executables that feel like Elixir modules.**

### 1.2 Goals

- **Seamless Integration** — Native builds triggered automatically by `mix compile`
- **Smart Recompilation** — Source file tracking via `@external_resource` triggers rebuilds when native code changes
- **Platform Constraints** — Declare OS/architecture requirements; unsupported platforms skip compilation gracefully
- **Builder Agnostic** — Pluggable builder system supports Cargo, CMake, or custom build systems
- **Native Test Integration** — Run native tests via `mix foundry.test` with unified reporting
- **Minimal Dependencies** — No external build tool wrappers; only `ex_doc` for documentation

### 1.3 Non-Goals

- **NIF generation** — Foundry builds standalone executables spawned via Ports. For in-process Rust NIFs, use Rustler. Ports provide process isolation and crash safety at the cost of IPC overhead.
- **Make/Makefile support** — CMake is the C/C++ builder. Make lacks cross-platform consistency and structured configuration. Projects using Make can wrap it in a custom builder module.
- **Runtime binary downloads** — Binaries are built at compile time, not fetched. This ensures reproducible builds and avoids supply chain risks from downloading pre-built binaries.
- **Hot code reloading for native code** — Native binaries are static. Recompilation requires a full `mix compile` cycle. Hot reloading native code is fundamentally at odds with process isolation.

---

## 2. Configuration

### 2.1 Module DSL

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cargo,
    binaries: ["my_binary"]
end
```

### 2.2 Options Reference

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `:otp_app` | `atom()` | ✅ | — | OTP application name |
| `:builder` | `:cargo \| :cmake \| module()` | ✅ | — | Build system to use |
| `:binaries` | `[String.t()]` | ✅ | — | Binary names to build and copy |
| `:source_path` | `String.t()` | ❌ | Builder default | Path to native source directory |
| `:profile` | `String.t()` | ❌ | MIX_ENV-based | `"debug"` or `"release"` |
| `:env` | `[{String.t(), String.t()}]` | ❌ | `[]` | Environment variables for build |
| `:skip_compilation?` | `boolean()` | ❌ | `false` | Skip build, only copy binaries |
| `:os` | `[os()]` | ❌ | `nil` (any) | Required operating systems |
| `:arch` | `[arch()]` | ❌ | `nil` (any) | Required architectures |
| `:builder_opts` | `keyword()` | ❌ | `[]` | Builder-specific options |

### 2.3 Platform Types

```elixir
@type os :: :linux | :macos | :windows | :freebsd
@type arch :: :x86_64 | :arm64 | :arm
```

### 2.4 Profile Resolution

| MIX_ENV | Profile | Build Type |
|---------|---------|------------|
| `:prod` | `"release"` | Optimized, no debug symbols |
| `:dev` | `"debug"` | Debug symbols, fast compilation |
| `:test` | `"debug"` | Debug symbols, fast compilation |

---

## 3. Builder System

### 3.1 Builder Behaviour

Builders implement the `Foundry.Builder` behaviour:

```elixir
# Required callbacks
@callback default_source_path() :: String.t()
@callback validate_opts!(opts :: keyword()) :: :ok | no_return()
@callback build!(source_path :: String.t(), profile :: String.t(), opts :: keyword()) :: :ok | no_return()
@callback binary_paths(source_path :: String.t(), binaries :: [String.t()], profile :: String.t(), opts :: keyword()) :: %{String.t() => String.t()}
@callback discover_resources(source_path :: String.t()) :: [String.t()]

# Optional callbacks (for test support)
@callback test!(source_path :: String.t(), opts :: keyword()) :: test_result()
@callback supports_test?() :: boolean()

@type test_result :: %{status: :ok | :error, exit_code: non_neg_integer(), output: String.t()}
```

### 3.2 Built-in Builders

| Builder | Language | Default Source | Build Command |
|---------|----------|----------------|---------------|
| `:cargo` | Rust | `native/` | `cargo build [--release] [--target TARGET]` |
| `:cmake` | C/C++ | `c_src/` | `cmake -S . -B build && cmake --build build` |

### 3.3 Cargo Builder Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:cargo` | `:system \| {:bin, path}` | `:system` | Cargo binary location |
| `:target` | `String.t()` | `nil` | Rust target triple for cross-compilation |
| `:target_dir` | `String.t()` | `_build/<env>/native/<app>/target` | Cargo output directory |

**Cross-compilation example:**

```elixir
use Foundry,
  otp_app: :my_app,
  builder: :cargo,
  binaries: ["my_binary"],
  builder_opts: [target: "aarch64-unknown-linux-gnu"]
```

### 3.4 CMake Builder Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:target` | `String.t()` | First binary name | CMake target to build |
| `:args` | `[String.t()]` | `[]` | Extra CMake configure arguments |
| `:build_dir` | `String.t()` | `_build/<env>/native/<app>/build` | CMake build directory |

**Custom CMake args example:**

```elixir
use Foundry,
  otp_app: :my_app,
  builder: :cmake,
  binaries: ["my_tool"],
  builder_opts: [args: ["-DENABLE_FEATURE=ON", "-DCUSTOM_PATH=/opt/lib"]]
```

### 3.5 Custom Builders

Custom builders implement the `Foundry.Builder` behaviour:

```elixir
defmodule MyApp.Builder.Meson do
  @behaviour Foundry.Builder

  @impl true
  def default_source_path, do: "meson_src"

  @impl true
  def validate_opts!(opts), do: :ok

  @impl true
  def build!(source_path, profile, opts) do
    # Run meson setup + compile
    :ok
  end

  @impl true
  def binary_paths(_source_path, binaries, _profile, opts) do
    # Return map of binary name to built path
  end

  @impl true
  def discover_resources(source_path) do
    # Return list of source files to watch
  end
end
```

---

## 4. Compilation Pipeline

### 4.1 Pipeline Stages

```
use Foundry, opts
        │
        ▼
┌───────────────────┐
│ 1. Parse & Merge  │  Merge env config + opts
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 2. Validate       │  Check required fields
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 3. Resolve        │  Apply defaults (source_path, profile)
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 4. Platform Check │  Match OS/arch constraints
└───────────────────┘
        │
        ├─── Unsupported ──► Skip build, generate error functions
        │
        ▼
┌───────────────────┐
│ 5. Build          │  Run builder (cargo/cmake/custom)
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 6. Copy           │  Move binaries to priv/
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 7. Discover       │  Collect source files for @external_resource
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ 8. Generate       │  Emit path helper functions
└───────────────────┘
```

### 4.2 Build Output Locations

| Component | Path |
|-----------|------|
| Cargo target dir | `_build/<env>/native/<app>/target/` |
| CMake build dir | `_build/<env>/native/<app>/build/` |
| Final binaries | `_build/<env>/lib/<app>/priv/` |

### 4.3 Recompilation Tracking

The `discover_resources/1` callback returns source files registered via `@external_resource`. Mix triggers recompilation when any tracked file changes.

**Cargo tracked files:**
- `Cargo.toml`, `Cargo.lock`
- `**/Cargo.toml` (workspace members)
- `**/*.rs` (excluding `/target/`)

**CMake tracked files:**
- `CMakeLists.txt`, `CMakePresets.json`
- `src/**/*.{c,cc,cpp,cxx,h,hpp}`

---

## 5. Generated Functions

### 5.1 Supported Platform Functions

When the current platform matches constraints:

```elixir
@doc "Returns the path to a binary copied into priv/"
def bin_path(name) :: String.t()

@doc "Absolute path to the <name> binary under priv/"
def <name>_path() :: String.t()

@doc "Returns true - this module's binaries are available"
def platform_supported?() :: true

@doc "Returns the required OS list (nil means any)"
def required_os() :: [os()] | nil

@doc "Returns the required architecture list (nil means any)"
def required_arch() :: [arch()] | nil
```

### 5.2 Unsupported Platform Functions

When the current platform does not match constraints:

```elixir
@doc "Raises UnsupportedPlatformError"
def bin_path(name) :: no_return()

@doc "Raises UnsupportedPlatformError"
def <name>_path() :: no_return()

@doc "Returns false - this module's binaries are not available"
def platform_supported?() :: false

def required_os() :: [os()] | nil
def required_arch() :: [arch()] | nil
```

### 5.3 Binary Name Normalization

Binary names with hyphens are converted to underscores for function names:

| Binary Name | Generated Function |
|-------------|-------------------|
| `my-tool` | `my_tool_path/0` |
| `gst_file_sink` | `gst_file_sink_path/0` |

---

## 6. Platform Constraints

### 6.1 Constraint Matching

Platform constraints use AND logic between OS and architecture:

```elixir
# Matches: Linux on x86_64 or arm64
use Foundry,
  os: [:linux],
  arch: [:x86_64, :arm64],
  ...

# Matches: Any OS on x86_64
use Foundry,
  arch: [:x86_64],
  ...

# Matches: Linux or macOS on any architecture
use Foundry,
  os: [:linux, :macos],
  ...
```

### 6.2 Constraint Behavior

| Scenario | Compile-time | Runtime |
|----------|--------------|---------|
| Platform matches | Build executes | Path functions return paths |
| Platform doesn't match | Build skipped with message | Path functions raise `UnsupportedPlatformError` |
| No constraints | Build executes | Path functions return paths |

### 6.3 UnsupportedPlatformError

```elixir
%Foundry.UnsupportedPlatformError{
  binary: String.t(),
  required_os: [os()] | nil,
  required_arch: [arch()] | nil
}
```

The exception message includes human-readable platform descriptions:

```
Binary "my_tool" is not available on this platform.
Current: linux/x86_64
Required: macos/arm64
```

---

## 7. Integration Patterns

### 7.1 Port Spawning

```elixir
defmodule MyApp.Worker do
  def start do
    port = Port.open(
      {:spawn_executable, MyApp.Native.my_binary_path()},
      [:binary, :exit_status, {:args, ["--config", config_path()]}]
    )
    {:ok, port}
  end
end
```

### 7.2 Conditional Compilation

```elixir
defmodule MyApp.Processor do
  if MyApp.Native.platform_supported?() do
    def process(data) do
      # Use native binary
      run_native(data)
    end
  else
    def process(data) do
      # Fallback to pure Elixir
      run_elixir(data)
    end
  end
end
```

### 7.3 Runtime Platform Check

```elixir
def process(data) do
  if MyApp.Native.platform_supported?() do
    run_native(data)
  else
    run_fallback(data)
  end
end
```

---

## 8. Native Testing

### 8.1 Overview

Foundry provides `mix foundry.test` to run native tests (Cargo tests, gtest via CMake) with unified reporting. Tests are discovered automatically from Foundry modules.

### 8.2 Mix Task

```bash
# Run all native tests
mix foundry.test

# Run tests for a specific module
mix foundry.test --only MyApp.Native

# Verbose output (show all test output)
mix foundry.test --verbose

# Pass arguments to underlying test runner
mix foundry.test -- --nocapture          # cargo test args
mix foundry.test -- -R "pattern"         # ctest args
```

### 8.3 Cargo Test Support

The Cargo builder runs `cargo test` in the source directory:

```elixir
use Foundry,
  otp_app: :my_app,
  builder: :cargo,
  binaries: ["my_binary"],
  builder_opts: [
    test_args: ["--", "--nocapture"]  # Optional: pass args to cargo test
  ]
```

**Test execution:**
```
cargo test [--target TARGET] [test_args...]
```

### 8.4 CMake Test Support

The CMake builder configures with `-DBUILD_TESTING=ON`, builds tests, and runs `ctest`:

```elixir
use Foundry,
  otp_app: :my_app,
  builder: :cmake,
  binaries: ["my_binary"],
  builder_opts: [
    cmake_test_args: ["-DGTEST_ROOT=/path/to/gtest"],  # Extra CMake args for test build
    test_args: ["-R", "unit_"]  # ctest filter pattern
  ]
```

**Test execution pipeline:**
```
cmake -S source -B build_test -DBUILD_TESTING=ON [cmake_test_args...]
cmake --build build_test
ctest --test-dir build_test/test --output-on-failure [test_args...]
```

### 8.5 Test Result Format

```elixir
@type test_result :: %{
  status: :ok | :error,
  exit_code: non_neg_integer(),
  output: String.t()
}
```

### 8.6 Custom Builder Test Support

Custom builders implement the optional test callbacks:

```elixir
defmodule MyApp.Builder.Custom do
  @behaviour Foundry.Builder

  # ... required callbacks ...

  @impl true
  def supports_test?, do: true

  @impl true
  def test!(source_path, opts) do
    # Run your test command
    case System.cmd("my-test-runner", [], cd: source_path) do
      {output, 0} -> %{status: :ok, exit_code: 0, output: output}
      {output, code} -> %{status: :error, exit_code: code, output: output}
    end
  end
end
```

---

## 9. Testing Strategy

### 9.1 Invariants

| Invariant | Formal Statement | Test |
|-----------|------------------|------|
| **Binary copied** | `∀ b ∈ binaries: File.exists?(priv_path(b))` | `test_binaries_exist` |
| **Recompilation triggers** | `∀ f ∈ sources: touch(f) → recompile` | `test_external_resources` |
| **Platform gating** | `¬matches?(os, arch) → skip_build ∧ raise_on_access` | `test_unsupported_platform` |
| **Path normalization** | `bin_path("a-b") == "a-b" ∧ fun_name == :a_b_path` | `test_path_normalization` |
| **Native tests run** | `∀ m ∈ modules: supports_test?(m) → test!(m)` | `test_native_tests_run` |

### 9.2 Test Categories

| Test Type | Coverage | Tools |
|-----------|----------|-------|
| Unit | Builder option validation | ExUnit |
| Unit | Platform detection and matching | ExUnit |
| Integration | Full Cargo build cycle | ExUnit + Rust toolchain |
| Integration | Full CMake build cycle | ExUnit + CMake |
| Integration | Native test execution | ExUnit + Cargo/CMake |
| Property | Binary name normalization | StreamData (optional) |

### 9.3 Test Isolation

Tests use temporary directories and avoid polluting the global `_build/`:

```elixir
setup do
  tmp_dir = Path.join(System.tmp_dir!(), "foundry_test_#{:rand.uniform(100_000)}")
  File.mkdir_p!(tmp_dir)
  on_exit(fn -> File.rm_rf!(tmp_dir) end)
  {:ok, tmp_dir: tmp_dir}
end
```

---

## 10. Trade-offs

### 10.1 Ports vs NIFs

| Criterion | Ports (Foundry) | NIFs (Rustler) |
|-----------|-----------------|----------------|
| Crash isolation | ✅ Process boundary | ❌ Crashes BEAM |
| Performance | ⚠️ IPC overhead | ✅ Direct memory access |
| Complexity | ✅ Spawn + communicate | ⚠️ FFI bindings |
| Debugging | ✅ Separate process | ⚠️ Mixed stack traces |
| Hot reload | ❌ Requires restart | ❌ Requires restart |
| **Best for** | **CLI tools, crash-prone code** | **Performance-critical, stable code** |

**Decision:** Foundry targets Ports. The IPC overhead is acceptable for CLI tools and services where crash isolation is more valuable than raw performance.

### 10.2 Compile-time vs Runtime Download

| Criterion | Compile-time Build | Runtime Download |
|-----------|-------------------|------------------|
| Reproducibility | ✅ Deterministic | ⚠️ Version drift |
| Build time | ⚠️ Slower CI | ✅ Fast compile |
| Supply chain | ✅ Source auditable | ❌ Binary trust |
| Offline builds | ✅ After first build | ❌ Requires network |
| **Decision** | **Selected** | Rejected |

**Trade-off accepted:** Longer compile times are acceptable for reproducibility and security.

---

## Appendix A: Directory Structure

```
my_app/
├── lib/
│   └── my_app/
│       └── native.ex              # use Foundry module
├── native/                        # Cargo source (default)
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── main.rs
├── c_src/                         # CMake source (default)
│   ├── CMakeLists.txt
│   └── src/
│       └── main.cpp
└── _build/
    └── dev/
        ├── native/
        │   └── my_app/
        │       ├── target/        # Cargo output
        │       └── build/         # CMake output
        └── lib/
            └── my_app/
                └── priv/
                    └── my_binary  # Final binary location
```

---

## Appendix B: Keyword Index

| Category | Keywords |
|----------|----------|
| **Modules** | `Foundry`, `Foundry.Compiler`, `Foundry.Builder`, `Foundry.Builder.Cargo`, `Foundry.Builder.CMake`, `Foundry.Platform`, `Foundry.BinaryUtils`, `Foundry.UnsupportedPlatformError` |
| **Options** | `:otp_app`, `:builder`, `:binaries`, `:source_path`, `:profile`, `:env`, `:skip_compilation?`, `:os`, `:arch`, `:builder_opts` |
| **Cargo Options** | `:cargo`, `:target`, `:target_dir` |
| **CMake Options** | `:target`, `:args`, `:build_dir` |
| **Platforms** | `:linux`, `:macos`, `:windows`, `:freebsd`, `:x86_64`, `:arm64`, `:arm` |
| **Functions** | `bin_path/1`, `<name>_path/0`, `platform_supported?/0`, `required_os/0`, `required_arch/0` |

---

## Changelog

### v1.1 (2026-01-26)

- **Added:** Native test integration via `mix foundry.test`
- **Added:** `test!/2` and `supports_test?/0` optional callbacks in Builder behaviour
- **Added:** Cargo builder test support (`cargo test`)
- **Added:** CMake builder test support (gtest via `ctest`)
- **Added:** Section 8 documenting native testing
- **Changed:** Section numbers updated (Testing Strategy → 9, Trade-offs → 10)

### v1.0 (2026-01-26)

- Initial specification
