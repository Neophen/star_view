if Code.ensure_loaded?(Phoenix.HTML.Safe) do
  defimpl Phoenix.HTML.Safe, for: StarView.Template do
    def to_iodata(template), do: StarView.Template.to_iodata(template)
  end
end
