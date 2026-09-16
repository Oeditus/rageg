defmodule RagegWeb.OAuthMetadataController do
  @moduledoc """
  Serves OAuth 2.0 Protected Resource Metadata (RFC 9728) for the Tidewave
  MCP endpoint.

  MCP clients that connect to a remote/authenticated MCP server discover the
  authorization server(s) they should use by fetching the protected resource's
  well-known metadata document. Tidewave's `/tidewave/mcp` endpoint is
  development-only and does not itself implement OAuth, so this document is a
  "somewhat reasonable" placeholder: it advertises the MCP endpoint as the
  protected resource and points at a placeholder authorization server.

  The canonical RFC 9728 location for a resource at `/tidewave/mcp` would be
  `/.well-known/oauth-protected-resource/tidewave/mcp`; we additionally serve
  the bare `/.well-known/oauth-protected-resource` path for convenience.
  """

  use RagegWeb, :controller

  @doc """
  Renders the protected resource metadata document.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(metadata(conn))
  end

  @doc """
  Builds the RFC 9728 metadata document for the current request.

  The `resource` is derived from the incoming connection so that the document
  is correct regardless of host/port, and the resource path is the Tidewave MCP
  endpoint. `authorization_servers` is a placeholder pointing back at this
  application, since no external authorization server is configured.
  """
  @spec metadata(Plug.Conn.t()) :: map()
  def metadata(conn) do
    base = base_url(conn)

    %{
      "resource" => base <> "/tidewave/mcp",
      "authorization_servers" => [base],
      "bearer_methods_supported" => ["header"],
      "scopes_supported" => ["mcp"],
      "resource_documentation" => base <> "/tidewave"
    }
  end

  defp base_url(conn) do
    scheme = conn.scheme |> to_string()
    port = conn.port

    if (scheme == "http" and port == 80) or (scheme == "https" and port == 443) do
      "#{scheme}://#{conn.host}"
    else
      "#{scheme}://#{conn.host}:#{port}"
    end
  end
end
