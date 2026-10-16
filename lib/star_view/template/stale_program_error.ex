defmodule StarView.Template.StaleProgramError do
  @moduledoc "A compiled snapshot's rendering code changed. Build a fresh template."
  defexception message:
                 "compiled ~STAR program is unavailable after a code reload; build a fresh template"
end
