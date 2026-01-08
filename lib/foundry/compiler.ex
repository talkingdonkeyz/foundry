defmodule Foundry.Compiler do
  @moduledoc false

  @type builder :: :cargo | :cmake | module()
  @type os :: :linux | :macos | :windows | :freebsd
  @type arch :: :x86_64 | :arm64 | :arm

  @type t :: %__MODULE__{
          otp_app: atom(),
          builder: builder(),
          source_path: String.t(),
          binaries: [String.t()],
          profile: String.t() | nil,
          env: [{String.t(), String.t()}],
          external_resources: [String.t()],
          skip_compilation?: boolean(),
          builder_opts: keyword(),
          os: [os()] | nil,
          arch: [arch()] | nil,
          platform_supported?: boolean()
        }

  defstruct otp_app: nil,
            builder: nil,
            source_path: nil,
            binaries: [],
            profile: nil,
            env: [],
            external_resources: [],
            skip_compilation?: false,
            builder_opts: [],
            os: nil,
            arch: nil,
            platform_supported?: true

  @spec compile(atom(), keyword(), keyword()) :: t()
  def compile(otp_app, env, opts) do
    %__MODULE__{}
    |> merge_env(env)
    |> merge_opts(otp_app, opts)
    |> ensure_required!()
    |> resolve_defaults()
    |> resolve_profile()
    |> check_platform_support()
    |> validate_builder_opts!()
    |> do_compile()
  end

  defp check_platform_support(%__MODULE__{} = config) do
    supported? = Foundry.Platform.matches?(config.os, config.arch)
    %__MODULE__{config | platform_supported?: supported?}
  end

  defp do_compile(%__MODULE__{platform_supported?: false} = config) do
    current = Foundry.Platform.description()
    required = Foundry.Platform.constraints_description(config.os, config.arch)

    Mix.shell().info(
      "Skipping #{config.otp_app} native build (unsupported platform: #{current}, requires: #{required})"
    )

    %__MODULE__{config | external_resources: []}
  end

  defp do_compile(%__MODULE__{} = config) do
    source_path = resolve_source_path(config.source_path)

    if File.dir?(source_path) do
      config = %__MODULE__{config | source_path: source_path}
      builder_mod = Foundry.Builder.get!(config.builder)

      builder_opts =
        config.builder_opts
        |> Keyword.put(:env, config.env)
        |> Keyword.put(:otp_app, config.otp_app)
        |> Keyword.put(:binaries, config.binaries)

      unless config.skip_compilation? do
        builder_mod.build!(config.source_path, config.profile, builder_opts)
      end

      binary_paths =
        builder_mod.binary_paths(
          config.source_path,
          config.binaries,
          config.profile,
          builder_opts
        )

      priv_dir = ensure_priv_dir()
      dests = Foundry.BinaryUtils.copy_binaries!(binary_paths, priv_dir)

      externals = dests ++ builder_mod.discover_resources(config.source_path)
      %__MODULE__{config | external_resources: externals}
    else
      Mix.shell().info("No #{source_path} directory found, skipping native build")
      %__MODULE__{config | source_path: source_path, external_resources: []}
    end
  end

  defp merge_env(config, env) when is_list(env) do
    Enum.reduce(env, config, &merge_opt/2)
  end

  defp merge_opts(config, otp_app, opts) do
    opts
    |> Keyword.put(:otp_app, otp_app)
    |> Enum.reduce(config, &merge_opt/2)
  end

  defp merge_opt({:otp_app, value}, config) when is_atom(value), do: %{config | otp_app: value}
  defp merge_opt({:builder, value}, config) when is_atom(value), do: %{config | builder: value}

  defp merge_opt({:source_path, value}, config) when is_binary(value),
    do: %{config | source_path: value}

  defp merge_opt({:binaries, value}, config) when is_list(value) do
    %{config | binaries: Enum.map(value, &to_string/1)}
  end

  defp merge_opt({:profile, value}, config) when is_binary(value), do: %{config | profile: value}
  defp merge_opt({:env, value}, config) when is_list(value), do: %{config | env: value}

  defp merge_opt({:skip_compilation?, value}, config) when is_boolean(value),
    do: %{config | skip_compilation?: value}

  defp merge_opt({:builder_opts, value}, config) when is_list(value),
    do: %{config | builder_opts: value}

  defp merge_opt({:os, value}, config) when is_list(value), do: %{config | os: value}
  defp merge_opt({:arch, value}, config) when is_list(value), do: %{config | arch: value}
  defp merge_opt(_, config), do: config

  defp ensure_required!(%__MODULE__{otp_app: nil}), do: Mix.raise("Foundry requires :otp_app")

  defp ensure_required!(%__MODULE__{builder: nil}),
    do: Mix.raise("Foundry requires :builder option")

  defp ensure_required!(%__MODULE__{binaries: []}) do
    Mix.raise("Foundry requires :binaries option with at least one binary")
  end

  defp ensure_required!(config), do: config

  defp resolve_defaults(%__MODULE__{source_path: nil} = config) do
    builder_mod = Foundry.Builder.get!(config.builder)
    %{config | source_path: builder_mod.default_source_path()}
  end

  defp resolve_defaults(config), do: config

  defp resolve_profile(%__MODULE__{profile: nil} = cfg) do
    profile = if Mix.env() == :prod, do: "release", else: "debug"
    %__MODULE__{cfg | profile: profile}
  end

  defp resolve_profile(cfg), do: cfg

  defp validate_builder_opts!(%__MODULE__{platform_supported?: false} = config), do: config

  defp validate_builder_opts!(%__MODULE__{} = config) do
    builder_mod = Foundry.Builder.get!(config.builder)
    builder_mod.validate_opts!(config.builder_opts)
    config
  end

  defp resolve_source_path(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(app_root(), path)
    end
  end

  defp app_root do
    Mix.Project.app_path()
    |> Path.dirname()
    |> Path.dirname()
    |> Path.dirname()
    |> then(fn build_lib ->
      app = Mix.Project.config()[:app] |> to_string()
      apps_dir = Path.join(Path.dirname(build_lib), "apps")

      if File.dir?(apps_dir) do
        Path.join(apps_dir, app)
      else
        File.cwd!()
      end
    end)
  end

  defp ensure_priv_dir do
    priv_dir = Path.join(Mix.Project.app_path(), "priv")
    File.mkdir_p!(priv_dir)
    priv_dir
  end
end
