defmodule StarView.Scripts do
  @moduledoc """
  Script helpers implemented through Datastar element patches.
  """

  alias StarView.Elements
  alias StarView.JSON

  @doc """
  Executes JavaScript by appending a `<script>` element to `body`.
  """
  @spec execute(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def execute(conn, script, opts \\ []) when is_binary(script) do
    auto_remove = Keyword.get(opts, :auto_remove, true)
    attributes = Keyword.get(opts, :attributes, [])

    script_html =
      attributes
      |> normalize_attributes()
      |> maybe_add_auto_remove(auto_remove)
      |> script_tag(script)

    element_opts =
      opts
      |> Keyword.take([:event_id, :retry, :retry_duration])
      |> Keyword.merge(selector: "body", mode: :append)

    Elements.patch(conn, script_html, element_opts)
  end

  @doc """
  Redirects the browser to a URL.
  """
  @spec redirect(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def redirect(conn, url, opts \\ []) when is_binary(url) do
    execute(conn, "setTimeout(function(){window.location.href=#{JSON.encode!(url)}},0)", opts)
  end

  @doc """
  Logs a message in the browser console.
  """
  @spec console_log(Plug.Conn.t(), term(), keyword()) :: Plug.Conn.t()
  def console_log(conn, message, opts \\ []) do
    {level, opts} = Keyword.pop(opts, :level, :log)
    level = normalize_console_level(level)

    js_message = JSON.encode!(message)

    execute(conn, "console.#{level}(#{js_message})", opts)
  end

  @doc """
  Formats an execute-script element patch without writing to a connection.
  """
  @spec format_execute(String.t(), keyword()) :: String.t()
  def format_execute(script, opts \\ []) when is_binary(script) do
    auto_remove = Keyword.get(opts, :auto_remove, true)
    attributes = Keyword.get(opts, :attributes, [])

    script_html =
      attributes
      |> normalize_attributes()
      |> maybe_add_auto_remove(auto_remove)
      |> script_tag(script)

    element_opts =
      opts
      |> Keyword.take([:event_id, :retry, :retry_duration])
      |> Keyword.merge(selector: "body", mode: :append)

    Elements.format_patch(script_html, element_opts)
  end

  defp normalize_console_level(level) when level in [:log, :warn, :error, :info, :debug],
    do: Atom.to_string(level)

  defp normalize_console_level(level) when level in ["log", "warn", "error", "info", "debug"],
    do: level

  defp normalize_console_level(_level), do: "log"

  defp normalize_attributes(attributes) when is_map(attributes), do: Map.to_list(attributes)
  defp normalize_attributes(attributes) when is_list(attributes), do: attributes

  defp maybe_add_auto_remove(attributes, false), do: attributes

  defp maybe_add_auto_remove(attributes, true) do
    [{"data-effect", "el.remove()"} | attributes]
  end

  defp script_tag(attributes, script) do
    attrs =
      attributes
      |> Enum.map(&attribute_to_iodata/1)
      |> IO.iodata_to_binary()

    "<script#{attrs}>#{escape_script_content(script)}</script>"
  end

  defp attribute_to_iodata(attribute) when is_binary(attribute),
    do: [" ", validate_attr_name!(attribute)]

  defp attribute_to_iodata({key, true}), do: [" ", validate_attr_name!(key)]
  defp attribute_to_iodata({_key, false}), do: []
  defp attribute_to_iodata({_key, nil}), do: []

  defp attribute_to_iodata({key, value}) do
    [" ", validate_attr_name!(key), "=\"", escape_html_attr(to_string(value)), "\""]
  end

  @attr_name ~r/\A[A-Za-z0-9_:.-]+\z/

  defp validate_attr_name!(name) do
    name = to_string(name)

    if Regex.match?(@attr_name, name) do
      name
    else
      raise ArgumentError, "invalid script attribute name #{inspect(name)}"
    end
  end

  # Keep the original string's case while neutralizing the HTML closing tag.
  defp escape_script_content(script),
    do: Regex.replace(~r{</script}i, script, &escape_script_close/1)

  defp escape_script_close(match), do: "<\\" <> String.slice(match, 1..-1//1)

  defp escape_html_attr(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
