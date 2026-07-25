defmodule Rageg.AIKeys do
  @moduledoc """
  Manages AI provider keys and dynamic configuration for Ragex.
  Persists keys in `~/.rageg/.ai_keys.json`.
  """

  @config_file "~/.rageg/.ai_keys.json"

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
  """
  def save_config(params) do
    file_path = Path.expand(@config_file)
    File.mkdir_p!(Path.dirname(file_path))

    data = %{
      "deepseek_r1" => params[:deepseek_r1] || params["deepseek_r1"],
      "openai" => params[:openai] || params["openai"],
      "anthropic" => params[:anthropic] || params["anthropic"],
      "default_provider" => to_string(params[:default_provider] || params["default_provider"]),
      "fallback_enabled" => !!(params[:fallback_enabled] || params["fallback_enabled"])
    }

    File.write!(file_path, Jason.encode!(data, pretty: true))
    load_keys()
  end

  @doc """
  Returns the active keys and options map.
  """
  def get_config do
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

  defp decode_json({:ok, content}) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      _ -> :error
    end
  end

  defp decode_json(_), do: :error
end
