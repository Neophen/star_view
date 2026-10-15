locals_without_parens = [
  star_view: 2,
  star_view: 3,
  star_view_components: 0,
  star_view_components: 1,
  star_view_components: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Quokka, StarView.Template.Formatter],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
