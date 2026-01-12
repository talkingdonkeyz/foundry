# Foundry

[![Hex.pm](https://img.shields.io/hexpm/v/foundry.svg)](https://hex.pm/packages/foundry)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/foundry)
[![CI](https://github.com/talkingdonkeyz/foundry/actions/workflows/ci.yml/badge.svg)](https://github.com/talkingdonkeyz/foundry/actions/workflows/ci.yml)

**Native executables that feel like Elixir modules.**

Foundry makes working with native code (Rust, C/C++) just as ergonomic as writing Elixir. Just add `use Foundry` to a module, and it handles the build, tracks source changes for automatic recompilation, and generates path helper functions—all during `mix compile`.

Perfect for spawning external tools as Erlang Ports, whether you're wrapping a Rust CLI, a C++ image processor, or any standalone executable. No Rust experience required—if you can add a dependency, you can use Foundry.

## Features

- 🦀 **Cargo support** — Build Rust projects
- 🔧 **CMake support** — Build C/C++ projects
- ♻️ **Smart recompilation** — Tracks source files and only rebuilds when they change (not on every `mix compile`)
- 📍 **Path helpers** — Generated functions to locate your binaries
- 🔌 **Zero configuration** — Sensible defaults, just add `use Foundry`

## Installation

Add `foundry` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:foundry, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Rust (Cargo)

1. Create a Rust project in `native/`:

```
my_app/
├── lib/
│   └── my_app/
│       └── native.ex
├── native/
│   ├── Cargo.toml
│   └── src/
│       └── main.rs
└── mix.exs
```

2. Add a Native module:

```elixir
# lib/my_app/native.ex
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cargo,
    binaries: ["my_binary"]
end
```

3. Run `mix compile` — your binary is now in `priv/`!

4. Use the generated path helpers:

```elixir
# Generic lookup
MyApp.Native.bin_path("my_binary")
#=> "/path/to/_build/dev/lib/my_app/priv/my_binary"

# Generated convenience function
MyApp.Native.my_binary_path()
#=> "/path/to/_build/dev/lib/my_app/priv/my_binary"
```

### C/C++ (CMake)

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cmake,
    binaries: ["my_tool"],
    source_path: "c_src"  # default for cmake
end
```

## Spawning as a Port

The typical use case is spawning the binary as an Erlang Port:

```elixir
defmodule MyApp.Runner do
  def start do
    exe = MyApp.Native.my_binary_path()

    Port.open({:spawn_executable, exe}, [
      :binary,
      :exit_status,
      args: ["--some-flag", "value"]
    ])
  end
end
```

## Configuration Options

### Common Options

| Option               | Type                         | Default                                | Description                                         |
| -------------------- | ---------------------------- | -------------------------------------- | --------------------------------------------------- |
| `:otp_app`           | `atom`                       | _required_                             | Your application name                               |
| `:builder`           | `atom`                       | _required_                             | Build system (`:cargo`, `:cmake`, or custom module) |
| `:binaries`          | `[String.t()]`               | _required_                             | List of binary names to copy                        |
| `:source_path`       | `String.t()`                 | `"native"` (cargo) / `"c_src"` (cmake) | Path to native source                               |
| `:profile`           | `String.t()`                 | Based on `MIX_ENV`                     | Build profile (any string)                          |
| `:skip_compilation?` | `boolean`                    | `false`                                | Skip build, only copy                               |
| `:env`               | `[{String.t(), String.t()}]` | `[]`                                   | Environment variables for build                     |
| `:builder_opts`      | `keyword()`                  | `[]`                                   | Builder-specific options (see below)                |

### Cargo Builder Options

Pass these in `builder_opts` when using `builder: :cargo`:

| Option        | Type                      | Default                            | Description                        |
| ------------- | ------------------------- | ---------------------------------- | ---------------------------------- |
| `:target`     | `String.t()`              | `nil`                              | Rust target triple (cross-compile) |
| `:cargo`      | `:system \| {:bin, path}` | `:system`                          | Cargo binary to use                |
| `:target_dir` | `String.t()`              | `_build/<env>/native/<app>/target` | Cargo output directory             |

### CMake Builder Options

Pass these in `builder_opts` when using `builder: :cmake`:

| Option       | Type           | Default                           | Description                |
| ------------ | -------------- | --------------------------------- | -------------------------- |
| `:target`    | `String.t()`   | First binary                      | CMake target name to build |
| `:args`      | `[String.t()]` | `[]`                              | Extra CMake arguments      |
| `:build_dir` | `String.t()`   | `_build/<env>/native/<app>/build` | CMake build directory      |

### Custom Builders

You can implement your own builder by creating a module that implements the `Foundry.Builder` behaviour:

```elixir
defmodule MyApp.MakeBuilder do
  @behaviour Foundry.Builder

  @impl true
  def default_source_path, do: "c_src"

  @impl true
  def validate_opts!(_opts), do: :ok

  @impl true
  def build!(source_path, profile, opts) do
    env = Keyword.get(opts, :env, [])
    {_, 0} = System.cmd("make", [profile], cd: source_path, env: env)
    :ok
  end

  @impl true
  def binary_paths(source_path, binaries, _profile, _opts) do
    Map.new(binaries, fn name ->
      {name, Path.join([source_path, "bin", name])}
    end)
  end

  @impl true
  def discover_resources(source_path) do
    Path.wildcard(Path.join(source_path, "**/*.{c,h}"))
  end
end
```

Then use it:

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: MyApp.MakeBuilder,
    binaries: ["my_tool"]
end
```

## How It Works

### Compile-Time Magic

When you `use Foundry`, the macro:

1. **Runs the build** at compile time via `cargo build` or `cmake`
2. **Copies binaries** from the build output to `_build/<env>/lib/<app>/priv/`
3. **Registers external resources** using `@external_resource` for automatic recompilation
4. **Generates helper functions** for runtime path lookup

### Automatic Recompilation

Foundry watches your source files:

**Cargo projects:**

- `Cargo.toml`, `Cargo.lock`
- All `*.rs` files (excluding `target/`)

**CMake projects:**

- `CMakeLists.txt`, `CMakePresets.json`
- All `src/**/*.{c,cpp,h,hpp}` files

When any of these change, Mix knows to recompile your Native module, triggering a fresh native build.

## Examples

### Cross-Compilation (Rust)

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cargo,
    binaries: ["my_binary"],
    builder_opts: [target: "aarch64-unknown-linux-gnu"]
end
```

### Custom Cargo Location

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cargo,
    binaries: ["my_binary"],
    builder_opts: [cargo: {:bin, "/usr/local/bin/cargo"}]
end
```

### CMake with Extra Arguments

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cmake,
    binaries: ["my_tool"],
    builder_opts: [args: ["-DENABLE_FEATURE=ON", "-DCUSTOM_VAR=value"]]
end
```

### Build Environment Variables

Pass environment variables to the build process via the `:env` option:

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cmake,
    binaries: ["my_nif"],
    env: [
      {"CC", "clang"},
      {"CXX", "clang++"},
      {"ERL_EI_INCLUDE_DIR", "/usr/lib/erlang/usr/include"},
      {"ERL_EI_LIB_DIR", "/usr/lib/erlang/usr/lib"}
    ]
end
```

### Release Builds

Foundry automatically uses release builds when `MIX_ENV=prod`:

```bash
MIX_ENV=prod mix compile
```

Or override explicitly:

```elixir
use Foundry,
  otp_app: :my_app,
  builder: :cargo,
  binaries: ["my_binary"],
  profile: "release"
```

### Custom Profiles

The `:profile` option accepts any string, so you can use custom Cargo profiles or CMake build types:

```elixir
# Cargo custom profile (defined in Cargo.toml)
use Foundry,
  otp_app: :my_app,
  builder: :cargo,
  binaries: ["my_binary"],
  profile: "release-lto"

# CMake RelWithDebInfo
use Foundry,
  otp_app: :my_app,
  builder: :cmake,
  binaries: ["my_tool"],
  profile: "RelWithDebInfo"
```

### Multiple Binaries

```elixir
defmodule MyApp.Native do
  use Foundry,
    otp_app: :my_app,
    builder: :cargo,
    binaries: ["tool_a", "tool_b", "tool_c"]
end

# Generated functions:
MyApp.Native.tool_a_path()
MyApp.Native.tool_b_path()
MyApp.Native.tool_c_path()
```

## Comparison with Other Tools

| Tool                                                      | Use Case                        | Languages               | Tracks Source Changes | Path Helpers           | Config Required            |
| --------------------------------------------------------- | ------------------------------- | ----------------------- | --------------------- | ---------------------- | -------------------------- |
| **Foundry**                                               | Standalone executables as Ports | Rust, C/C++, extensible | ✅                    | ✅ Generated functions | Minimal—just `use Foundry` |
| [Rustler](https://github.com/rusterlium/rustler)          | Rust NIFs (in-process)          | Rust only               | ✅                    | ✅                     | Minimal                    |
| [elixir_make](https://github.com/elixir-lang/elixir_make) | Run `make` during compile       | Any (manual)            | ❌                    | ❌                     | Manual Makefile + hooks    |
| [bundlex](https://github.com/membraneframework/bundlex)   | Membrane framework NIFs         | C/C++                   | ❌                    | ✅                     | Moderate                   |

## Why Foundry?

If you need to spawn executables as Ports (not NIFs), Foundry gives you Rustler-level DX:

- **Rebuilds only when needed** — Foundry tracks your native source files (`.rs`, `.c`, `Cargo.toml`, etc.) and only triggers a rebuild when they change. No wasted time on every `mix compile`.
- **Generated path helpers** — Get type-safe functions to locate your binaries at runtime. No manual path concatenation.
- **Zero-config defaults** — Just `use Foundry`. No Makefiles, no manual dependency tracking, no custom Mix tasks.

Unlike `elixir_make`, you don't write scripts to track dependencies or find compiled binaries. Unlike always-rebuilding tools, you don't wait for unnecessary recompilation.

## License

MIT License - see [LICENSE](LICENSE) for details.
