defmodule RagegWeb.Plugs.Locale do
  @moduledoc """
  Plug that sets the Gettext locale from session, query param, or
  Accept-Language header.

  Precedence: `?locale=` query param > session > Accept-Language > default ("en").

  Supported locales: `en`, `es`, `ca`.
  """

  import Plug.Conn

  @supported_locales ~w(en es ca)
  @default_locale "en"

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    locale =
      conn.params["locale"] ||
        get_session(conn, :locale) ||
        parse_accept_language(conn) ||
        @default_locale

    locale = if locale in @supported_locales, do: locale, else: @default_locale

    Gettext.put_locale(RagegWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  defp parse_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> String.split(",")
        |> Enum.map(fn part ->
          part |> String.split(";") |> hd() |> String.trim() |> String.downcase()
        end)
        |> Enum.find(fn lang ->
          String.slice(lang, 0, 2) in @supported_locales
        end)
        |> case do
          nil -> nil
          lang -> String.slice(lang, 0, 2)
        end

      _ ->
        nil
    end
  end
end
