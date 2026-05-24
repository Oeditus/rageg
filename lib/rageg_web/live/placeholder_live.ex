for {module, path, title, icon, description, phase} <- [
      {RagegWeb.EmbeddingsLive, "/embeddings", "Embedding Space", "hero-sparkles",
       "2D projection of code entity embeddings with semantic search", 6},
      {RagegWeb.AnalyzeLive, "/analyze", "Run Analysis", "hero-play-circle",
       "Project analyzer with live progress and configurable analyses", 8}
    ] do
  defmodule module do
    @moduledoc """
    #{title} -- Phase #{phase}.

    #{description}.

    This is a placeholder that will be implemented in Phase #{phase}.
    """
    use RagegWeb, :live_view

    @page_title title
    @current_path path
    @icon icon
    @description description
    @phase phase

    @impl Phoenix.LiveView
    def mount(_params, _session, socket) do
      {:ok,
       socket
       |> assign(page_title: gettext(@page_title))
       |> assign(current_path: @current_path)}
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      assigns =
        assigns
        |> assign(:icon, @icon)
        |> assign(:title, @page_title)
        |> assign(:description, @description)
        |> assign(:phase, @phase)

      ~H"""
      <div class="hero min-h-[60vh]">
        <div class="hero-content text-center">
          <div class="max-w-md">
            <.icon name={@icon} class="size-16 text-primary mx-auto mb-4" />
            <h1 class="text-3xl font-bold">{@title}</h1>
            <p class="py-4 text-base-content/70">{@description}</p>
            <div class="badge badge-outline">Phase {@phase}</div>
          </div>
        </div>
      </div>
      """
    end
  end
end
