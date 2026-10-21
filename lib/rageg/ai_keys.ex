defmodule Rageg.AIKeys do
  @moduledoc """
  Manages AI provider keys and dynamic configuration for Ragex.
  Persists keys in `~/.rageg/.ai_keys.json`.

  ## Security

  Real key values are only ever read server-side. `get_config/0` returns
  **masked** placeholders (e.g. `"••••1234"`) so the browser never receives a
  secret. Use `get_raw_config/0` for server-side needs (tests, internal tooling).

  The config file is written with `0o600` permissions. Keys are still stored in
  plaintext on disk; for stronger protection use the OS keychain (a future
  improvement, not yet implemented).
  """

  @config_file "~/.rageg/.ai_keys.json"
  @mask_prefix "••••"
  @providers ~w(deepseek_r1 openai anthropic ollama)

  @doc """
  Loads the persisted keys and re-evaluates the active providers list.
  Sets `:ragex` `:ai_keys` and `:ai` configurations.
  """
  def load_keys do
    file_path = Path.expand(@config_file)

    file_keys =
      if File.exists?(file_path) do
        case File.read(file_path) |> decode_json() do
          {:ok, data} -> data
          _ -> %{}
        end
      else
        %{}
      end

    deepseek_key = Map.get(file_keys, "deepseek_r1") || System.get_env("DEEPSEEK_API_KEY")
    openai_key = Map.get(file_keys, "openai") || System.get_env("OPENAI_API_KEY")
    anthropic_key = Map.get(file_keys, "anthropic") || System.get_env("ANTHROPIC_API_KEY")

    default_provider =
      case Map.get(file_keys, "default_provider") || System.get_env("RAGEX_DEFAULT_PROVIDER") do
        "openai" -> :openai
        "anthropic" -> :anthropic
        "ollama" -> :ollama
        _ -> :deepseek_r1
      end

    fallback_enabled = Map.get(file_keys, "fallback_enabled", false)

    keys = [
      deepseek_r1: deepseek_key,
      openai: openai_key,
      anthropic: anthropic_key
    ]

    Application.put_env(:ragex, :ai_keys, keys)

    providers =
      [:deepseek_r1]
      |> then(fn list -> if openai_key && openai_key != "", do: [:openai | list], else: list end)
      |> then(fn list ->
        if anthropic_key && anthropic_key != "", do: [:anthropic | list], else: list
      end)
      |> then(fn list ->
        if System.get_env("OLLAMA_API_ENDPOINT") || default_provider == :ollama,
          do: [:ollama | list],
          else: list
      end)
      |> Enum.uniq()
      |> then(fn list -> [default_provider | list] end)
      |> Enum.uniq()

    Application.put_env(:ragex, :ai,
      providers: providers,
      default_provider: default_provider,
      fallback_enabled: fallback_enabled
    )
  end

  @doc """
  Saves the keys/options map to `~/.rageg/.ai_keys.json` and updates the running config.

  Keys are only overwritten when a *new* value is supplied. Blank values and
  masked placeholders (e.g. `"••••1234"`) preserve the currently stored key, so
  a form submission that did not change a key cannot clobber it.
  """
  def save_config(params) do
    file_path = Path.expand(@config_file)
    existing = get_raw_config()

    data = %{
      "deepseek_r1" =>
        resolve_secret(params[:deepseek_r1] || params["deepseek_r1"], existing.deepseek_r1),
      "openai" => resolve_secret(params[:openai] || params["openai"], existing.openai),
      "anthropic" =>
        resolve_secret(params[:anthropic] || params["anthropic"], existing.anthropic),
      "default_provider" => to_string(params[:default_provider] || params["default_provider"]),
      "fallback_enabled" => !!(params[:fallback_enabled] || params["fallback_enabled"])
    }

    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, Jason.encode!(data, pretty: true))
    _ = File.chmod(file_path, 0o600)
    load_keys()
  end

  @doc """
  Returns the active keys and options map with **masked** placeholders.

  Real key values are never returned to callers that may forward them to a
  client (e.g. the configuration LiveView).
  """
  def get_config do
    raw = get_raw_config()

    %{
      deepseek_r1: mask(raw.deepseek_r1),
      openai: mask(raw.openai),
      anthropic: mask(raw.anthropic),
      default_provider: raw.default_provider,
      fallback_enabled: raw.fallback_enabled
    }
  end

  @doc """
  Returns the active keys and options map with the real key values.

  Intended for server-side use only (tests, internal tooling). Never pass this
  map to a template or client.
  """
  def get_raw_config do
    keys = Application.get_env(:ragex, :ai_keys, [])
    ai = Application.get_env(:ragex, :ai, [])

    %{
      deepseek_r1: keys[:deepseek_r1] || "",
      openai: keys[:openai] || "",
      anthropic: keys[:anthropic] || "",
      default_provider: ai[:default_provider] || :deepseek_r1,
      fallback_enabled: ai[:fallback_enabled] || false
    }
  end

  @doc "Returns the list of supported provider names (strings)."
  @spec providers() :: [String.t()]
  def providers, do: @providers

  # -- Private --

  # Preserve the existing secret when the incoming value is blank or masked.
  defp resolve_secret(nil, existing), do: existing

  defp resolve_secret(value, existing) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> existing
      String.starts_with?(trimmed, @mask_prefix) -> existing
      true -> trimmed
    end
  end

  defp mask(value) when is_binary(value) and value != "" do
    if String.length(value) > 4 do
      @mask_prefix <> String.slice(value, -4, 4)
    else
      @mask_prefix
    end
  end

  defp mask(_), do: ""

  defp decode_json({:ok, content}) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      _ -> :error
    end
  end

  defp decode_json(_), do: :error
end
