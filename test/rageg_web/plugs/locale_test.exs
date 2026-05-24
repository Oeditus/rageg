defmodule RagegWeb.Plugs.LocaleTest do
  use RagegWeb.ConnCase, async: true

  alias RagegWeb.Plugs.Locale

  describe "call/2" do
    test "defaults to en locale", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.fetch_query_params()
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "reads locale from query param", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "es"})
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "reads locale from session", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.fetch_query_params()
        |> init_test_session(%{locale: "ca"})
        |> Locale.call([])

      assert conn.assigns.locale == "ca"
    end

    test "rejects unsupported locale and falls back to en", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "zh"})
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "query param takes precedence over session", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"locale" => "ca"})
        |> init_test_session(%{locale: "es"})
        |> Locale.call([])

      assert conn.assigns.locale == "ca"
    end
  end
end
