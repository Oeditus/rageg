defmodule RagegWeb.ChatLive do
  @moduledoc """
  RAG Chat -- AI-powered codebase Q&A with streaming and tool-call visibility.

  Features:
  - Chat message bubbles with markdown rendering
  - Streaming tokens via LiveView async/stream
  - Tool-call sidebar showing the ReAct loop trace
  - Provider selector (DeepSeek, OpenAI, Anthropic, Ollama)
  - Session management (new session, end session)
  - Multi-turn conversation with memory
  """

  use RagegWeb, :live_view

  alias Rageg.Chat

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("RAG Chat"))
     |> assign(current_path: "/chat")
     |> assign(session_id: nil)
     |> assign(messages: [])
     |> assign(input: "")
     |> assign(sending: false)
     |> assign(streaming_content: "")
     |> assign(tool_calls: [])
     |> assign(provider: :deepseek_r1)
     |> assign(show_tools: false)
     |> assign(error: nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("new_session", _params, socket) do
    case Chat.new_session(provider: socket.assigns.provider) do
      {:ok, session_id} ->
        {:noreply,
         assign(socket, session_id: session_id, messages: [], tool_calls: [], error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: to_string(reason))}
    end
  end

  def handle_event("end_session", _params, socket) do
    if socket.assigns.session_id, do: Chat.end_session(socket.assigns.session_id)
    {:noreply, assign(socket, session_id: nil, messages: [], tool_calls: [])}
  end

  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    session_id = socket.assigns.session_id

    unless session_id do
      {:noreply, assign(socket, error: gettext("Start a session first"))}
    else
      # Add user message to UI immediately
      user_msg = %{role: :user, content: message, timestamp: DateTime.utc_now()}
      messages = socket.assigns.messages ++ [user_msg]
      pid = self()

      # Start async task for AI response
      Task.start(fn ->
        result =
          Chat.send_message(session_id, message,
            provider: socket.assigns.provider,
            on_chunk: fn chunk ->
              send(pid, {:stream_chunk, chunk})
            end,
            on_tool_progress: fn tool_info ->
              send(pid, {:tool_progress, tool_info})
            end
          )

        send(pid, {:chat_response, result})
      end)

      {:noreply,
       socket
       |> assign(messages: messages, input: "", sending: true, streaming_content: "")}
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, input: value)}
  end

  def handle_event("change_provider", %{"provider" => provider}, socket) do
    {:noreply, assign(socket, provider: String.to_existing_atom(provider))}
  end

  def handle_event("toggle_tools", _params, socket) do
    {:noreply, assign(socket, show_tools: !socket.assigns.show_tools)}
  end

  @impl Phoenix.LiveView
  def handle_info({:rageg_profile_changed, _profile}, socket) do
    {:noreply, socket}
  end

  def handle_info({:stream_chunk, chunk}, socket) do
    content = chunk[:content] || chunk["content"] || ""
    current = socket.assigns.streaming_content

    {:noreply, assign(socket, streaming_content: current <> content)}
  end

  def handle_info({:tool_progress, tool_info}, socket) do
    tool_calls = socket.assigns.tool_calls ++ [tool_info]
    {:noreply, assign(socket, tool_calls: tool_calls)}
  end

  def handle_info({:chat_response, {:ok, result}}, socket) do
    content = result.content || socket.assigns.streaming_content
    assistant_msg = %{role: :assistant, content: content, timestamp: DateTime.utc_now()}
    messages = socket.assigns.messages ++ [assistant_msg]

    {:noreply,
     socket
     |> assign(messages: messages, sending: false, streaming_content: "", error: nil)}
  end

  def handle_info({:chat_response, {:error, reason}}, socket) do
    {:noreply, assign(socket, sending: false, error: to_string(reason))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-8rem)]">
      <%!-- Header bar --%>
      <div class="flex items-center gap-3 pb-3 border-b border-base-300">
        <h1 class="text-lg font-bold">{gettext("RAG Chat")}</h1>

        <%!-- Provider selector --%>
        <select
          class="select select-sm select-bordered"
          phx-change="change_provider"
          name="provider"
        >
          <option
            :for={{key, label} <- Chat.providers()}
            value={key}
            selected={key == @provider}
          >
            {label}
          </option>
        </select>

        <div class="flex-1"></div>

        <%!-- Tool calls toggle --%>
        <button
          class={["btn btn-sm btn-ghost gap-1", if(@show_tools, do: "btn-active", else: "")]}
          phx-click="toggle_tools"
        >
          <.icon name="hero-wrench-screwdriver" class="size-4" />
          {gettext("Tools")} ({length(@tool_calls)})
        </button>

        <%!-- Session controls --%>
        <button :if={!@session_id} class="btn btn-sm btn-primary" phx-click="new_session">
          {gettext("New Session")}
        </button>
        <button :if={@session_id} class="btn btn-sm btn-ghost btn-error" phx-click="end_session">
          {gettext("End Session")}
        </button>
      </div>

      <%!-- Error banner --%>
      <div :if={@error} class="alert alert-error mt-2">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>

      <%!-- Main content --%>
      <div class="flex flex-1 min-h-0 mt-3 gap-3">
        <%!-- Chat messages --%>
        <div class="flex-1 flex flex-col min-h-0">
          <%!-- Messages area --%>
          <div id="chat-messages" class="flex-1 overflow-y-auto space-y-3 pr-2" phx-update="replace">
            <div
              :if={@messages == [] and !@session_id}
              class="flex items-center justify-center h-full"
            >
              <div class="text-center text-base-content/40">
                <.icon name="hero-chat-bubble-left-right" class="size-16 mx-auto mb-3" />
                <p class="text-lg font-medium">{gettext("Start a new session to begin chatting")}</p>
                <p class="text-sm mt-1">{gettext("Ask questions about your codebase")}</p>
              </div>
            </div>

            <div :if={@messages == [] and @session_id} class="flex items-center justify-center h-full">
              <div class="text-center text-base-content/40">
                <.icon name="hero-sparkles" class="size-12 mx-auto mb-2" />
                <p>{gettext("Session ready. Ask a question!")}</p>
              </div>
            </div>

            <.message_bubble :for={msg <- @messages} message={msg} />

            <%!-- Streaming indicator --%>
            <div :if={@sending and @streaming_content != ""} class="chat chat-start">
              <div class="chat-bubble chat-bubble-primary whitespace-pre-wrap text-sm">
                {@streaming_content}
                <span class="loading loading-dots loading-xs ml-1"></span>
              </div>
            </div>

            <div :if={@sending and @streaming_content == ""} class="chat chat-start">
              <div class="chat-bubble chat-bubble-primary">
                <span class="loading loading-dots loading-sm"></span>
              </div>
            </div>
          </div>

          <%!-- Input area --%>
          <form
            :if={@session_id}
            id="chat-form"
            phx-submit="send_message"
            phx-change="update_input"
            class="mt-3 flex gap-2"
          >
            <input
              type="text"
              name="message"
              value={@input}
              placeholder={gettext("Ask about your codebase...")}
              class="input input-bordered flex-1"
              autocomplete="off"
              disabled={@sending}
            />
            <button type="submit" class="btn btn-primary" disabled={@sending or @input == ""}>
              <.icon name="hero-paper-airplane" class="size-5" />
            </button>
          </form>
        </div>

        <%!-- Tool calls sidebar --%>
        <div
          :if={@show_tools and @tool_calls != []}
          class="w-72 shrink-0 overflow-y-auto rounded-box bg-base-200 border border-base-300 p-3 space-y-2"
        >
          <h3 class="text-xs font-bold uppercase tracking-wider text-base-content/60">
            {gettext("Tool Calls")}
          </h3>
          <div
            :for={{tool, idx} <- Enum.with_index(@tool_calls, 1)}
            class="text-xs bg-base-100 rounded-box p-2 space-y-1"
          >
            <div class="flex items-center gap-1">
              <span class="badge badge-xs badge-primary">{idx}</span>
              <span class="font-mono font-semibold">{tool[:name] || tool["name"] || "tool"}</span>
            </div>
            <div :if={tool[:arguments] || tool["arguments"]} class="text-base-content/50 truncate">
              {inspect(tool[:arguments] || tool["arguments"])}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Components --

  attr :message, :map, required: true

  defp message_bubble(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div class="chat chat-end">
      <div class="chat-bubble whitespace-pre-wrap text-sm">{@message.content}</div>
    </div>
    """
  end

  defp message_bubble(%{message: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="chat chat-start">
      <div class="chat-bubble chat-bubble-primary whitespace-pre-wrap text-sm">
        {@message.content}
      </div>
    </div>
    """
  end

  defp message_bubble(assigns) do
    ~H"""
    <div class="chat chat-start">
      <div class="chat-bubble chat-bubble-accent whitespace-pre-wrap text-xs opacity-60">
        {@message.content}
      </div>
    </div>
    """
  end
end
