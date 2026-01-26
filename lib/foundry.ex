defmodule Foundry do
  @moduledoc """
  Rustler-inspired hook that builds native code during compilation and copies
  resulting binaries into the caller app's `priv/` directory.

  ## Usage

      defmodule MyApp.Native do
        use Foundry,
          otp_app: :my_app,
          builder: :cargo,
          binaries: ["my_binary"]
      end

  ## Platform Constraints

  Use `:os` and `:arch` to restrict builds to specific platforms:

      use Foundry,
        otp_app: :my_app,
        builder: :cmake,
        binaries: ["my_tool"],
        os: [:linux],           # Only build on Linux
        arch: [:x86_64, :arm64] # Only build on x86_64 or arm64

  When constraints are specified but the current platform doesn't match,
  compilation is skipped and accessing the binary at runtime raises
  `Foundry.UnsupportedPlatformError`.

  ## Builder-Specific Options

  Use the `:builder_opts` key to pass builder-specific options:

      # Cargo with cross-compilation
      use Foundry,
        otp_app: :my_app,
        builder: :cargo,
        binaries: ["my_binary"],
        builder_opts: [target: "aarch64-unknown-linux-gnu"]

      # CMake with custom target
      use Foundry,
        otp_app: :my_app,
        builder: :cmake,
        binaries: ["my_tool"],
        builder_opts: [target: "my_cmake_target", args: ["-DFOO=bar"]]

  See `Foundry.Builder.Cargo` and `Foundry.Builder.CMake` for
  builder-specific options.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = Keyword.fetch!(opts, :otp_app)
      env = Application.compile_env(otp_app, __MODULE__, [])
      config = Foundry.Compiler.compile(otp_app, env, opts)

      Enum.each(config.external_resources, fn resource ->
        @external_resource resource
      end)

      @foundry_otp_app otp_app
      @foundry_binaries config.binaries
      @foundry_platform_supported config.platform_supported?
      @foundry_os config.os
      @foundry_arch config.arch
      @foundry_config config
      @before_compile Foundry
    end
  end

  defmacro __before_compile__(env) do
    binaries = Module.get_attribute(env.module, :foundry_binaries)
    otp_app = Module.get_attribute(env.module, :foundry_otp_app)
    platform_supported? = Module.get_attribute(env.module, :foundry_platform_supported)
    os = Module.get_attribute(env.module, :foundry_os)
    arch = Module.get_attribute(env.module, :foundry_arch)
    config = Module.get_attribute(env.module, :foundry_config)

    config_func = generate_config_function(config)

    platform_funcs =
      if platform_supported? do
        generate_supported_functions(otp_app, binaries, os, arch)
      else
        generate_unsupported_functions(binaries, os, arch)
      end

    quote do
      unquote(config_func)
      unquote(platform_funcs)
    end
  end

  defp generate_config_function(config) do
    # Convert struct to map for serialization
    config_map = %{
      otp_app: config.otp_app,
      builder: config.builder,
      source_path: config.source_path,
      binaries: config.binaries,
      profile: config.profile,
      env: config.env,
      builder_opts: config.builder_opts,
      os: config.os,
      arch: config.arch,
      platform_supported?: config.platform_supported?
    }

    quote do
      @doc false
      def __foundry_config__ do
        unquote(Macro.escape(config_map))
      end
    end
  end

  defp generate_supported_functions(otp_app, binaries, os, arch) do
    binary_funcs =
      Enum.map(binaries, fn bin ->
        fun_name =
          bin
          |> String.replace("-", "_")
          |> then(&:"#{&1}_path")

        quote do
          @doc "Absolute path to the #{unquote(bin)} binary under priv/"
          def unquote(fun_name)() do
            Application.app_dir(unquote(otp_app), Path.join("priv", unquote(bin)))
          end
        end
      end)

    quote do
      @doc "Returns the path to a binary copied into priv/"
      def bin_path(name) when is_binary(name) do
        Application.app_dir(unquote(otp_app), Path.join("priv", name))
      end

      @doc "Returns true - this module's binaries are available on the current platform"
      def platform_supported?, do: true

      @doc "Returns the required OS list for this module's binaries (nil means any)"
      def required_os, do: unquote(Macro.escape(os))

      @doc "Returns the required architecture list for this module's binaries (nil means any)"
      def required_arch, do: unquote(Macro.escape(arch))

      unquote_splicing(binary_funcs)
    end
  end

  defp generate_unsupported_functions(binaries, os, arch) do
    binary_funcs =
      Enum.map(binaries, fn bin ->
        fun_name =
          bin
          |> String.replace("-", "_")
          |> then(&:"#{&1}_path")

        quote do
          @doc "Absolute path to the #{unquote(bin)} binary under priv/ (unavailable on this platform)"
          def unquote(fun_name)() do
            raise Foundry.UnsupportedPlatformError,
              binary: unquote(bin),
              required_os: unquote(Macro.escape(os)),
              required_arch: unquote(Macro.escape(arch))
          end
        end
      end)

    quote do
      @doc "Returns the path to a binary copied into priv/ (unavailable on this platform)"
      def bin_path(name) when is_binary(name) do
        raise Foundry.UnsupportedPlatformError,
          binary: name,
          required_os: unquote(Macro.escape(os)),
          required_arch: unquote(Macro.escape(arch))
      end

      @doc "Returns false - this module's binaries are not available on the current platform"
      def platform_supported?, do: false

      @doc "Returns the required OS list for this module's binaries"
      def required_os, do: unquote(Macro.escape(os))

      @doc "Returns the required architecture list for this module's binaries"
      def required_arch, do: unquote(Macro.escape(arch))

      unquote_splicing(binary_funcs)
    end
  end
end
