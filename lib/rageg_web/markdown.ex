defmodule RagegWeb.Markdown do
  @moduledoc """
  Shared Markdown rendering for AI and analysis output.

  Centralises the MDEx pipeline (GFM, Mermaid, KaTeX, multiline cells) plus
  the `ide://open?path=...&line=...` link rewriting that was previously
  duplicated across `ChatLive`, `AuditLive`, and `AssessLive`.

  The rewritten links emit `phx-click="open_in_ide"` events; the LiveView must
  handle that event by delegating to `RagegWeb.EditorOpener.open/2`.
  """

  @ide_link_re ~r/<a href="ide:\/\/open\?path=([^"&]+)(?:&|&amp;)line=(\d+)">([^<]+)<\/a>/
  @code_path_re ~r/\b((?:lib|web|test|config|assets|src|app)\/[\w\-\.\/]+\.(?:exs?|py|rb|js|ts|json|heex|html|css))(?::(\d+))?\b/

  @doc """
  Renders markdown to sanitized-ish HTML with IDE links converted to
  LiveView click handlers. Returns `Phoenix.HTML.raw/1` content.
  """
  @spec render(String.t() | nil) :: Phoenix.HTML.safe() | String.t()
  def render(nil), do: ""

  def render(text) when is_binary(text) do
    case Code.ensure_loaded(MDEx) do
      {:module, MDEx} ->
        case text
             |> insert_intermediate_links()
             |> MDEx.to_html(plugins: [MDExGFM, MDExMermaid, MDExKatex, MdexMultilineCells]) do
          {:ok, html} ->
            html
            |> convert_ide_links()
            |> Phoenix.HTML.raw()

          {:error, _} ->
            text
        end

      _ ->
        text
    end
  end

  @doc """
  Renders markdown to plain HTML without IDE-link rewriting (used by the
  assessment report, which already contains resolved references).
  """
  @spec to_html(String.t() | nil) :: String.t()
  def to_html(nil), do: ""

  def to_html(markdown) when is_binary(markdown) do
    case MDEx.to_html(markdown, plugins: [MDExGFM, MDExMermaid, MDExKatex, MdexMultilineCells]) do
      {:ok, html} ->
        html

      {:error, _reason} ->
        markdown
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
    end
  end

  @doc false
  def insert_intermediate_links(text) do
    Regex.replace(@code_path_re, text, fn _full, path, line ->
      line_num = if line == "", do: "1", else: line
      display = if line == "", do: path, else: "#{path}:#{line}"
      "[#{display}](ide://open?path=#{path}&line=#{line_num})"
    end)
  end

  @doc false
  def convert_ide_links(html) do
    Regex.replace(@ide_link_re, html, fn _full, path, line, display ->
      ~s|<a href="#" phx-click="open_in_ide" phx-value-path="#{path}" phx-value-line="#{line}" class="underline text-primary font-mono cursor-pointer hover:opacity-80">#{display}</a>|
    end)
  end
end
