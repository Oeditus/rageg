import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/rageg start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :rageg, RagegWeb.Endpoint, server: true
end

config :rageg, RagegWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# dllb client connection pool & storage backend configuration
default_dllb_enabled = if config_env() == :test, do: "false", else: "true"
dllb_enabled = System.get_env("DLLB_ENABLED", default_dllb_enabled) in ["true", "1"]

config :dllb,
  enabled: dllb_enabled,
  host: System.get_env("DLLB_HOST", "127.0.0.1"),
  port: String.to_integer(System.get_env("DLLB_PORT", "3009")),
  pool_size: String.to_integer(System.get_env("DLLB_POOL_SIZE", "5")),
  timeout: String.to_integer(System.get_env("DLLB_TIMEOUT", "30000"))

if dllb_enabled do
  config :ragex, :store_backend, :dllb
  config :metastatic, :cache, :dllb
else
  config :ragex, :store_backend, :ets
  config :metastatic, :cache, :ets
end

# Ragex AI provider configuration.
# `Ragex.AI.Config` reads configuration from `:ai` and `:ai_providers`, and keys from `:ai_keys`.
# All of these are configured dynamically here to avoid compile-time bindings.
default_provider =
  case System.get_env("RAGEX_DEFAULT_PROVIDER") do
    "openai" -> :openai
    "anthropic" -> :anthropic
    "ollama" -> :ollama
    _ -> :deepseek_r1
  end

# Build list of active/configured providers at runtime.
# By default, deepseek_r1 is always included. Other providers are included if
# their corresponding API keys or endpoints are configured.
providers =
  [:deepseek_r1]
  |> then(fn list -> if System.get_env("OPENAI_API_KEY"), do: [:openai | list], else: list end)
  |> then(fn list ->
    if System.get_env("ANTHROPIC_API_KEY"), do: [:anthropic | list], else: list
  end)
  |> then(fn list ->
    if System.get_env("OLLAMA_API_ENDPOINT") || default_provider == :ollama,
      do: [:ollama | list],
      else: list
  end)
  |> Enum.uniq()
  |> then(fn list -> [default_provider | list] end)
  |> Enum.uniq()

config :ragex, :ai,
  providers: providers,
  default_provider: default_provider,
  fallback_enabled: false

config :ragex, :ai_providers,
  deepseek_r1: [
    endpoint: System.get_env("DEEPSEEK_API_ENDPOINT", "https://api.deepseek.com"),
    model: System.get_env("DEEPSEEK_MODEL", "deepseek-chat"),
    options: [temperature: 0.7, max_tokens: 2048, stream: false]
  ],
  openai: [
    endpoint: System.get_env("OPENAI_API_ENDPOINT", "https://api.openai.com/v1"),
    model: System.get_env("OPENAI_MODEL", "gpt-4-turbo"),
    options: [temperature: 0.7, max_tokens: 2048, stream: false]
  ],
  anthropic: [
    endpoint: System.get_env("ANTHROPIC_API_ENDPOINT", "https://api.anthropic.com/v1"),
    model: System.get_env("ANTHROPIC_MODEL", "claude-3-sonnet-20240229"),
    options: [temperature: 0.7, max_tokens: 2048]
  ],
  ollama: [
    endpoint: System.get_env("OLLAMA_API_ENDPOINT", "http://localhost:11434"),
    model: System.get_env("OLLAMA_MODEL", "codellama"),
    options: [temperature: 0.7, max_tokens: 2048]
  ]

config :ragex, :ai_keys,
  deepseek_r1: System.get_env("DEEPSEEK_API_KEY"),
  openai: System.get_env("OPENAI_API_KEY"),
  anthropic: System.get_env("ANTHROPIC_API_KEY")

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :rageg, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :rageg, RagegWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :rageg, RagegWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :rageg, RagegWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
