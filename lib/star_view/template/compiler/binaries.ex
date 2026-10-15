defmodule StarView.Template.Compiler.Binaries do
  @moduledoc false

  # Like Phoenix LiveView 1.2.12's MIT-licensed HTMLEngine, split known binary
  # attributes so fixed JavaScript/URL text is escaped once during compilation.

  def extract(binary) when is_binary(binary), do: {:ok, [binary]}
  def extract({:<>, _, [left, right]}), do: {:ok, operand(left) ++ operand(right)}

  def extract({:<<>>, _, parts}) do
    Enum.reduce_while(parts, {:ok, []}, &part/2)
  end

  def extract(_expression), do: :error

  defp operand(expression) do
    case extract(expression) do
      {:ok, parts} -> parts
      :error -> [{:dynamic, expression}]
    end
  end

  defp part(binary, {:ok, parts}) when is_binary(binary), do: {:cont, {:ok, parts ++ [binary]}}

  defp part({:"::", _, [expression, {:binary, _, _}]}, {:ok, parts}),
    do: {:cont, {:ok, parts ++ [{:dynamic, expression}]}}

  defp part(_unknown, _acc), do: {:halt, :error}
end
