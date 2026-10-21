defmodule RagegWeb.ErrorHTML do
  @moduledoc """
  Renders custom error pages for HTML requests.

  Replaces the plain-text default (`"Not Found"`, `"Internal Server Error"`)
  with a styled page that keeps the app's chrome-free look, explains what
  happened, and offers a way back. Unknown statuses fall back to the generic
  Phoenix status message so nothing is ever blank.
  """
  use RagegWeb, :html

  @doc false
  def render(template, assigns) do
    status = status_from_template(template)
    assigns = Map.put(assigns, :status, status)

    render_page(assigns)
  end

  defp render_page(%{status: 404} = assigns) do
    assigns =
      Map.merge(assigns, %{
        title: gettext("Page not found"),
        icon: "hero-map",
        message:
          gettext(
            "The page you are looking for does not exist. It may have moved, or the link may be stale."
          )
      })

    page(assigns)
  end

  defp render_page(%{status: 500} = assigns) do
    assigns =
      Map.merge(assigns, %{
        title: gettext("Something went wrong"),
        icon: "hero-exclamation-triangle",
        message:
          gettext(
            "An unexpected error occurred while rendering this page. The details were written to the server log."
          )
      })

    page(assigns)
  end

  defp render_page(%{status: status} = assigns) do
    assigns =
      Map.merge(assigns, %{
        title: Phoenix.Controller.status_message_from_template("#{status}.html"),
        icon: "hero-information-circle",
        message: gettext("The request could not be completed.")
      })

    page(assigns)
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :message, :string, required: true
  attr :status, :integer, required: true

  defp page(assigns) do
    ~H"""
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@status} · {@title}</title>
        <style>
          :root {
            color-scheme: light dark;
            --bg: #0f1115;
            --panel: #171a21;
            --text: #e6e8ee;
            --muted: #9aa3b2;
            --accent: #7c9cff;
          }
          @media (prefers-color-scheme: light) {
            :root {
              --bg: #f6f7fb;
              --panel: #ffffff;
              --text: #1b1f27;
              --muted: #5c6472;
              --accent: #3b5bdb;
            }
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background: var(--bg);
            color: var(--text);
            font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
            padding: 2rem;
          }
          main {
            max-width: 34rem;
            width: 100%;
            background: var(--panel);
            border-radius: 1rem;
            padding: 2.5rem;
            box-shadow: 0 20px 60px rgb(0 0 0 / 0.25);
            text-align: center;
          }
          .status {
            font-size: 0.75rem;
            letter-spacing: 0.2em;
            text-transform: uppercase;
            color: var(--muted);
          }
          h1 { margin: 0.75rem 0 0.5rem; font-size: 1.6rem; }
          p { margin: 0 0 1.75rem; color: var(--muted); line-height: 1.6; }
          a {
            display: inline-block;
            padding: 0.65rem 1.25rem;
            border-radius: 0.6rem;
            background: var(--accent);
            color: #fff;
            text-decoration: none;
            font-weight: 600;
            transition: transform 120ms ease, opacity 120ms ease;
          }
          a:hover { transform: translateY(-1px); opacity: 0.92; }
        </style>
      </head>
      <body>
        <main>
          <div class="status">{@status}</div>
          <h1>{@title}</h1>
          <p>{@message}</p>
          <a href="/">{gettext("Back to the dashboard")}</a>
        </main>
      </body>
    </html>
    """
  end

  defp status_from_template(template) do
    case Integer.parse(to_string(template)) do
      {status, _} -> status
      :error -> 500
    end
  end
end
