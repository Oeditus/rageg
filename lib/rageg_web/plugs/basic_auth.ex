defmodule RagegWeb.Plugs.BasicAuth do
  @moduledoc """
  Optional HTTP Basic authentication gate.

  Rageg is a powerful local tool: it can reset all state, run arbitrary dllb
  queries, execute MCP tools (including destructive ones), refactor files, and
  ingest arbitrary directories. If the app is reachable beyond loopback, it
  should not be left unauthenticated.

  Authentication is **disabled by default**. Enable it by configuring
  `config :rageg, :basic_auth, {"user", "password"}` (see `config/runtime.exs`,
  which reads `RAGEG_AUTH_USER` / `RAGEG_AUTH_PASSWORD`). When unset, this plug
  is a no-op so local development and tests are unaffected.
  """

  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    case Application.get_env(:rageg, :basic_auth) do
      {user, pass} when is_binary(user) and is_binary(pass) and user != "" and pass != "" ->
        authenticate(conn, user, pass)

      _ ->
        conn
    end
  end

  defp authenticate(conn, user, pass) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [got_user, got_pass] <- String.split(decoded, ":", parts: 2),
         true <-
           Plug.Crypto.secure_compare(got_user, user) and
             Plug.Crypto.secure_compare(got_pass, pass) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Rageg"))
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
