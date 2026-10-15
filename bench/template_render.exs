defmodule StarView.Bench.TemplateRender do
  @moduledoc """
  Reproduce rendering costs without a database or running web server.
  Run: mix run --no-start bench/template_render.exs
  STARVIEW_BENCH_SAMPLES controls samples. Measures the current compiler, with HEEx repeated.
  """
  import Phoenix.Component
  import StarView.Template.Sigils

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
    samples = System.get_env("STARVIEW_BENCH_SAMPLES", "1000") |> String.to_integer()
    Enum.each([10, 100, 1000], &measure(:heex, &1, "HEEx", samples))
    Enum.each([10, 100, 1000], &measure(:star, &1, "compiled", samples))
    Enum.each([10, 100, 1000], &measure(:heex, &1, "HEEx_repeat", samples))
  end

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
