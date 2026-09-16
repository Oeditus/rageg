defmodule RagegWeb.OAuthMetadataControllerTest do
  use RagegWeb.ConnCase, async: true

  alias RagegWeb.OAuthMetadataController

  describe "metadata/1" do
    test "advertises the Tidewave MCP endpoint as the protected resource" do
      conn =
        build_conn()
        |> Map.put(:host, "localhost")
        |> Map.put(:scheme, :http)
        |> Map.put(:port, 4000)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["resource"] == "http://localhost:4000/tidewave/mcp"
    end

    test "points authorization_servers at the current origin" do
      conn =
        build_conn()
        |> Map.put(:host, "localhost")
        |> Map.put(:scheme, :http)
        |> Map.put(:port, 4000)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["authorization_servers"] == ["http://localhost:4000"]
    end

    test "advertises bearer header auth and the mcp scope" do
      conn =
        build_conn()
        |> Map.put(:host, "localhost")
        |> Map.put(:scheme, :http)
        |> Map.put(:port, 4000)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["bearer_methods_supported"] == ["header"]
      assert "mcp" in metadata["scopes_supported"]
    end

    test "omits the default port for http on port 80" do
      conn =
        build_conn()
        |> Map.put(:host, "example.com")
        |> Map.put(:scheme, :http)
        |> Map.put(:port, 80)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["resource"] == "http://example.com/tidewave/mcp"
      assert metadata["authorization_servers"] == ["http://example.com"]
    end

    test "omits the default port for https on port 443" do
      conn =
        build_conn()
        |> Map.put(:host, "example.com")
        |> Map.put(:scheme, :https)
        |> Map.put(:port, 443)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["resource"] == "https://example.com/tidewave/mcp"
      assert metadata["authorization_servers"] == ["https://example.com"]
    end

    test "keeps a non-default https port" do
      conn =
        build_conn()
        |> Map.put(:host, "example.com")
        |> Map.put(:scheme, :https)
        |> Map.put(:port, 8443)

      metadata = OAuthMetadataController.metadata(conn)

      assert metadata["resource"] == "https://example.com:8443/tidewave/mcp"
    end
  end

  describe "show/2" do
    test "renders the metadata as JSON", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "localhost")
        |> Map.put(:scheme, :http)
        |> Map.put(:port, 4000)
        |> OAuthMetadataController.show(%{})

      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
      assert {"cache-control", "no-store"} in conn.resp_headers

      body = Jason.decode!(conn.resp_body)
      assert body["resource"] == "http://localhost:4000/tidewave/mcp"
      assert body["authorization_servers"] == ["http://localhost:4000"]
    end
  end
end
