defmodule RagegWeb.ConfigurationLive do
  @moduledoc """
  Configuration page -- manage AI provider API keys and default routing options.
  """

  use RagegWeb, :live_view

  alias Rageg.AIKeys

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    config = AIKeys.get_config()
    form_params = Map.new(config, fn {k, v} -> {to_string(k), v} end)

    {:ok,
     socket
     |> assign(page_title: gettext("Configuration"))
     |> assign(current_path: "/configuration")
     |> assign(config: config)
     |> assign(form: to_form(form_params, as: :config))
     |> assign(show_deepseek: false)
     |> assign(show_openai: false)
     |> assign(show_anthropic: false)
     |> assign(success_message: nil), layout: false}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_visibility", %{"field" => field}, socket) do
    case field do
      "deepseek" -> {:noreply, assign(socket, show_deepseek: !socket.assigns.show_deepseek)}
      "openai" -> {:noreply, assign(socket, show_openai: !socket.assigns.show_openai)}
      "anthropic" -> {:noreply, assign(socket, show_anthropic: !socket.assigns.show_anthropic)}
      _ -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"config" => config_params}, socket) do
    # Checkbox values in Phoenix forms submit "true"/"false" strings
    fallback_enabled = Map.get(config_params, "fallback_enabled") == "true"

    updated_params = %{
      deepseek_r1: Map.get(config_params, "deepseek_r1", "") |> String.trim(),
      openai: Map.get(config_params, "openai", "") |> String.trim(),
      anthropic: Map.get(config_params, "anthropic", "") |> String.trim(),
      default_provider:
        Map.get(config_params, "default_provider", "deepseek_r1") |> String.to_existing_atom(),
      fallback_enabled: fallback_enabled
    }

    case AIKeys.save_config(updated_params) do
      _ ->
        form_params = Map.new(updated_params, fn {k, v} -> {to_string(k), v} end)

        {:noreply,
         socket
         |> assign(config: updated_params)
         |> assign(form: to_form(form_params, as: :config))
         |> assign(success_message: gettext("Configuration saved successfully!"))}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("dismiss_success", _params, socket) do
    {:noreply, assign(socket, success_message: nil)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} page_title={@page_title}>
      <div class="space-y-6 max-w-4xl mx-auto">
        <div>
          <h1 class="text-2xl font-bold">{gettext("Configuration")}</h1>
          <p class="text-sm text-base-content/60">
            {gettext("Configure your AI model providers, API keys, and default routing settings.")}
          </p>
        </div>

        <%!-- Success Notification --%>
        <div :if={@success_message} class="alert alert-success shadow-lg flex justify-between items-center transition-all duration-300">
          <div class="flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-5" />
            <span>{@success_message}</span>
          </div>
          <button class="btn btn-ghost btn-xs" phx-click="dismiss_success">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="card bg-base-200 shadow-sm border border-base-300">
          <div class="card-body p-6">
            <.form for={@form} id="config-form" phx-submit="save" class="space-y-6">
              
              <%!-- API Keys Group --%>
              <div class="space-y-4">
                <h2 class="text-lg font-semibold border-b border-base-300 pb-2 flex items-center gap-2">
                  <.icon name="hero-key" class="size-5 text-primary" />
                  {gettext("API Keys")}
                </h2>

                <div class="grid grid-cols-1 gap-4">
                  <%!-- DeepSeek API Key --%>
                  <div>
                    <div class="flex justify-between items-end mb-1">
                      <label class="label-text font-medium">{gettext("DeepSeek R1 API Key")}</label>
                      <button
                        type="button"
                        class="text-xs text-primary hover:underline focus:outline-none flex items-center gap-1"
                        phx-click="toggle_visibility"
                        phx-value-field="deepseek"
                      >
                        <.icon name={if @show_deepseek, do: "hero-eye-slash", else: "hero-eye"} class="size-3.5" />
                        {if @show_deepseek, do: gettext("Hide"), else: gettext("Show")}
                      </button>
                    </div>
                    <.input
                      field={@form[:deepseek_r1]}
                      type={if @show_deepseek, do: "text", else: "password"}
                      placeholder="sk-..."
                      class="input input-bordered w-full font-mono"
                    />
                    <span class="text-xs text-base-content/50 mt-1 block">
                      {gettext("Used for DeepSeek chat and analysis models.")}
                    </span>
                  </div>

                  <%!-- OpenAI API Key --%>
                  <div>
                    <div class="flex justify-between items-end mb-1">
                      <label class="label-text font-medium">{gettext("OpenAI API Key")}</label>
                      <button
                        type="button"
                        class="text-xs text-primary hover:underline focus:outline-none flex items-center gap-1"
                        phx-click="toggle_visibility"
                        phx-value-field="openai"
                      >
                        <.icon name={if @show_openai, do: "hero-eye-slash", else: "hero-eye"} class="size-3.5" />
                        {if @show_openai, do: gettext("Hide"), else: gettext("Show")}
                      </button>
                    </div>
                    <.input
                      field={@form[:openai]}
                      type={if @show_openai, do: "text", else: "password"}
                      placeholder="sk-..."
                      class="input input-bordered w-full font-mono"
                    />
                    <span class="text-xs text-base-content/50 mt-1 block">
                      {gettext("Required if using OpenAI models.")}
                    </span>
                  </div>

                  <%!-- Anthropic API Key --%>
                  <div>
                    <div class="flex justify-between items-end mb-1">
                      <label class="label-text font-medium">{gettext("Anthropic API Key")}</label>
                      <button
                        type="button"
                        class="text-xs text-primary hover:underline focus:outline-none flex items-center gap-1"
                        phx-click="toggle_visibility"
                        phx-value-field="anthropic"
                      >
                        <.icon name={if @show_anthropic, do: "hero-eye-slash", else: "hero-eye"} class="size-3.5" />
                        {if @show_anthropic, do: gettext("Hide"), else: gettext("Show")}
                      </button>
                    </div>
                    <.input
                      field={@form[:anthropic]}
                      type={if @show_anthropic, do: "text", else: "password"}
                      placeholder="sk-ant-..."
                      class="input input-bordered w-full font-mono"
                    />
                    <span class="text-xs text-base-content/50 mt-1 block">
                      {gettext("Required if using Anthropic models.")}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Provider Options Group --%>
              <div class="space-y-4 pt-4 border-t border-base-300">
                <h2 class="text-lg font-semibold flex items-center gap-2">
                  <.icon name="hero-cpu-chip" class="size-5 text-primary" />
                  {gettext("Provider Settings")}
                </h2>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <%!-- Default Provider Selection --%>
                  <div>
                    <label class="label-text font-medium mb-1 block">{gettext("Default AI Provider")}</label>
                    <.input
                      field={@form[:default_provider]}
                      type="select"
                      options={[
                        {"DeepSeek R1", "deepseek_r1"},
                        {"OpenAI GPT", "openai"},
                        {"Anthropic Claude", "anthropic"},
                        {"Ollama (Local)", "ollama"}
                      ]}
                      class="select select-bordered w-full"
                    />
                    <span class="text-xs text-base-content/50 mt-1 block">
                      {gettext("Preferred default model provider for chats and reasoning.")}
                    </span>
                  </div>

                  <%!-- Fallback Switch --%>
                  <div class="flex flex-col justify-start">
                    <label class="label-text font-medium mb-2">{gettext("Automatic Provider Fallback")}</label>
                    <div class="flex items-center gap-3">
                      <.input
                        field={@form[:fallback_enabled]}
                        type="checkbox"
                        label={gettext("Enable multi-provider fallback")}
                        class="checkbox checkbox-primary"
                      />
                    </div>
                    <span class="text-xs text-base-content/50 mt-1 block">
                      {gettext("If the primary provider fails, automatically fall back to other configured keys.")}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Submit Section --%>
              <div class="flex justify-end pt-6 border-t border-base-300">
                <button type="submit" class="btn btn-primary px-8 gap-2">
                  <.icon name="hero-document-check" class="size-5" />
                  {gettext("Save Configuration")}
                </button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Information alert --%>
        <div class="alert alert-info bg-info/10 border-info/20 text-info flex gap-3 text-xs leading-relaxed">
          <.icon name="hero-information-circle" class="size-5 shrink-0 mt-0.5" />
          <div>
            <p class="font-semibold mb-1">{gettext("Security Notice")}</p>
            <p>
              {gettext("API keys saved here are stored locally on this machine in")} <code class="bg-base-300 px-1 py-0.5 rounded font-mono text-base-content">~/.rageg/.ai_keys.json</code>.
              {gettext("They are never sent to any telemetry server. System environment variables will serve as fallback defaults if GUI settings are not configured.")}
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
