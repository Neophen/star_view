defmodule StarView.Bench.TemplateRender do
  @moduledoc """
  Reproduce rendering costs without a database or running web server.
  Run: mix run --no-start bench/template_render.exs
  STARVIEW_BENCH_SAMPLES controls samples; STARVIEW_BENCH_BASELINE defaults to v0.6.0.
  """
  import Phoenix.Component
  import StarView.Template.Sigils

  @files ~w(html renderer runtime diff)

  def heex(assigns) do
    ~H"""
    <section id="results" class="space-y-4">
      <label :for={row <- @rows} id={row.id} class="flex items-center gap-3 rounded-xl border p-3">
        <input type="checkbox" value={row.id} checked={row.selected} />
        <span class="text-sm font-medium" title={row.title}>{row.title}</span>
      </label>
    </section>
    """
  end

  def star(assigns) do
    ~STAR"""
    <section id="results" class="space-y-4">
      <label :for={row <- @rows} id={row.id} class="flex items-center gap-3 rounded-xl border p-3">
        <input type="checkbox" value={row.id} checked={row.selected} />
        <span class="text-sm font-medium" title={row.title}>{row.title}</span>
      </label>
    </section>
    """
  end

  def run() do
    Code.compiler_options(ignore_module_conflict: true)
    samples = System.get_env("STARVIEW_BENCH_SAMPLES", "1000") |> String.to_integer()
    baseline = System.get_env("STARVIEW_BENCH_BASELINE", "v0.6.0")
    working = Enum.map(@files, &{path(&1), File.read!(path(&1))})
    Enum.each([10, 100, 1000], &measure(:heex, &1, "HEEx", samples))
    Enum.each(@files, &load_baseline(&1, baseline))
    Enum.each([10, 100, 1000], &measure(:star, &1, baseline, samples))
    Enum.each(working, &restore/1)
    Enum.each([10, 100, 1000], &measure(:star, &1, "working", samples))
  end

  defp path(name), do: "lib/star_view/template/#{name}.ex"

  defp load_baseline(name, ref) do
    {source, 0} = System.cmd("git", ["show", "#{ref}:#{path(name)}"])
    Code.compile_string(source, path(name))
  end

  defp restore({path, source}), do: Code.compile_string(source, path)

  defp measure(function, count, variant, samples) do
    rows =
      Enum.map(1..count, &%{id: "row-#{&1}", title: "City #{&1} <&>", selected: rem(&1, 5) == 0})

    assigns = %{rows: rows}
    action = fn -> apply(__MODULE__, function, [assigns]) |> encode() end
    Enum.each(1..100, fn _ -> action.() end)
    :erlang.garbage_collect()
    {:reductions, before} = Process.info(self(), :reductions)
    times = Enum.map(1..samples, fn _ -> elem(:timer.tc(action), 0) end)
    {:reductions, after_render} = Process.info(self(), :reductions)
    times = Enum.sort(times)
    html = action.()

    IO.puts(
      StarView.JSON.encode!(%{
        variant: variant,
        rows: count,
        samples: samples,
        median_us: Enum.at(times, div(samples, 2)),
        p95_us: Enum.at(times, min(div(samples * 95, 100), samples - 1)),
        reductions_per_render: div(after_render - before, samples),
        html_bytes: byte_size(html),
        gzip_bytes: byte_size(:zlib.gzip(html))
      })
    )
  end

  defp encode(template), do: template |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
end

StarView.Bench.TemplateRender.run()
