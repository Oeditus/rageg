defmodule Rageg.Chat do
  @moduledoc """
  Context module for the RAG Chat and Audit features.

  Wraps `Ragex.Agent.Core` and `Ragex.Agent.Memory` to manage chat
  sessions, streaming responses, and audit report generation for
  the LiveView pages.

  ## Session Lifecycle

  1. `new_session/1` -- creates a session with system prompt
  2. `send_message/3` -- sends user message, streams AI response via callback
  3. `get_messages/1` -- retrieves conversation history
  4. `end_session/1` -- cleans up

  ## Streaming

  The `send_message/3` function accepts an `:on_chunk` callback that
  receives content chunks as they arrive from the AI provider. The
  LiveView uses this to push tokens to the client in real-time.

  ## Audit

  `run_audit/2` triggers a full project analysis and report generation
  via `Ragex.Agent.Core.analyze_project/2`.
  """

  alias Ragex.Agent.{Core, Memory}

  @type session :: %{
          id: String.t(),
          created_at: DateTime.t()
        }

  @type message :: %{
          role: :user | :assistant | :system | :tool,
          content: String.t(),
          tool_calls: list() | nil,
          timestamp: DateTime.t()
        }

  @type chat_result :: %{
          content: String.t(),
          tool_calls_made: non_neg_integer(),
          usage: map()
        }

  @doc """
  Creates a new chat session.

  Sets up a system prompt instructing the AI to act as a code analysis
  assistant with access to Ragex MCP tools.

  ## Options

    * `:provider` - AI provider (:deepseek_r1, :openai, :anthropic, :ollama)
    * `:project_path` - project path for tool context

  ## Returns

  `{:ok, session_id}` or `{:error, reason}`
  """
  @spec new_session(keyword()) :: {:ok, String.t()} | {:error, term()}
  def new_session(opts \\ []) do
    project_path = Keyword.get(opts, :project_path)

    metadata = %{
      project_path: project_path,
      provider: Keyword.get(opts, :provider),
      created_at: DateTime.utc_now()
    }

    case Memory.new_session(metadata) do
      {:ok, session} ->
        system_prompt = build_system_prompt(project_path)
        Memory.add_message(session.id, :system, system_prompt)
        {:ok, session.id}

      error ->
        error
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Sends a user message and returns the AI response.

  Uses streaming when `:on_chunk` callback is provided.

  ## Options

    * `:on_chunk` - `(chunk -> :ok)` for streaming tokens
    * `:on_tool_progress` - `(map -> :ok)` for tool-call visibility
    * `:provider` - AI provider override

  ## Returns

  `{:ok, chat_result}` or `{:error, reason}`
  """
  @spec send_message(String.t(), String.t(), keyword()) ::
          {:ok, chat_result()} | {:error, term()}
  def send_message(session_id, message, opts \\ []) do
    if Keyword.has_key?(opts, :on_chunk) do
      Core.stream_chat(session_id, message, opts)
    else
      Core.chat(session_id, message, opts)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Retrieves the conversation history for a session.

  Returns messages in chronological order.
  """
  @spec get_messages(String.t()) :: {:ok, [message()]} | {:error, term()}
  def get_messages(session_id) do
    case Memory.get_messages(session_id) do
      {:ok, messages} ->
        formatted =
          messages
          |> Enum.map(fn msg ->
            %{
              role: msg.role,
              content: msg.content || "",
              tool_calls: msg[:tool_calls],
              timestamp: msg[:timestamp] || DateTime.utc_now()
            }
          end)
          |> Enum.reject(fn msg -> msg.role == :system end)

        {:ok, formatted}

      _ ->
        {:ok, []}
    end
  rescue
    _ -> {:ok, []}
  end

  @doc """
  Checks if a session is active.
  """
  @spec session_active?(String.t()) :: boolean()
  def session_active?(session_id) do
    Memory.session_exists?(session_id)
  rescue
    _ -> false
  end

  @doc """
  Ends a chat session and cleans up resources.
  """
  @spec end_session(String.t()) :: :ok
  def end_session(session_id) do
    Memory.clear_session(session_id)
  rescue
    _ -> :ok
  end

  @doc """
  Available AI providers with display names.
  """
  @spec providers() :: [{atom(), String.t()}]
  def providers do
    [
      {:deepseek_r1, "DeepSeek R1"},
      {:openai, "OpenAI"},
      {:anthropic, "Anthropic"},
      {:ollama, "Ollama"}
    ]
  end

  @doc """
  Runs a full project audit and returns the report.

  Triggers `Ragex.Agent.Core.analyze_project/2` which:
  1. Analyzes the codebase (builds knowledge graph)
  2. Discovers issues (security, smells, complexity, etc.)
  3. Generates an AI-polished audit report

  ## Options

    * `:provider` - AI provider
    * `:skip_analysis` - skip re-analysis, use cached graph (default: false)

  ## Returns

  `{:ok, %{report: string, session_id: string, summary: map}}` or `{:error, reason}`
  """
  @spec run_audit(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_audit(project_path, opts \\ []) do
    Core.analyze_project(project_path, opts)
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -- Private --

  defp build_system_prompt(project_path) do
    path_context =
      if project_path do
        """
        The project being analyzed is at: #{project_path}
        When using tools that require a path, use this project path.
        """
      else
        ""
      end

    """
    You are a code analysis assistant powered by Ragex.
    You have access to Ragex MCP tools for searching, querying, and analyzing code.

    #{path_context}

    Help the user understand their codebase by:
    - Answering questions about code structure and relationships
    - Finding functions, modules, and dependencies
    - Explaining complexity and quality metrics
    - Suggesting refactoring improvements

    Use the available tools to ground your answers in actual code analysis data.
    Be specific, cite file paths and function names.
    """
  end
end
