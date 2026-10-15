defmodule StarView.TemplateTest.Components do
  @moduledoc false
  use Phoenix.Component

  import StarView.Template.Sigils

  attr(:title, :string, required: true)
  slot(:inner_block, required: true)
  slot(:actions)

  def card(assigns) do
    ~STAR"""
    <article id="card">
      <h2>{@title}</h2>
      {render_slot(@inner_block)}
      <footer>{render_slot(@actions, "Action")}</footer>
    </article>
    """
  end

  def page(assigns) do
    ~STAR"""
    <main id="content">
      <.card title={@title}>
        <p id="greeting">{@name}</p>
        <:actions :let={label}><button>{label}</button></:actions>
      </.card>
    </main>
    """
  end

  def counter(assigns) do
    ~STAR"""
    <main id="content">
      <p id="counter">{@count}</p><h1 id="title">{@title}</h1>
    </main>
    """
  end

  def conditional(assigns) do
    ~STAR"""
    <main id="content">
      <%= if @shown do %>
        <p id="yes">{@name}</p>
      <% else %>
        <p id="no">Hidden</p>
      <% end %>
    </main>
    """
  end

  def directives(assigns) do
    ~STAR"""
    <ul id="items">
      <li :for={item <- @items} :if={item.visible} :key={item.id} id={"item-#{item.id}"}>
        {item.title}
      </li>
    </ul>
    """
  end

  def raw_for(assigns) do
    ~STAR"""
    <ul id="items">
      <%= for item <- @items do %>
        <li>{item.title}</li>
      <% end %>
    </ul>
    """
  end

  def escaped(assigns) do
    ~STAR"""
    <section id="content" title="A &amp; B">
      <input disabled={@disabled} class={["one", @class]} {@rest} />
      <p title={@value}>{@value}</p>
    </section>
    """
  end

  def mixed(assigns) do
    ~STAR"""
    <main id="content"><StarView.TemplateTest.Legacy.badge title={@title} /></main>
    """
  end

  def multiple_slots(assigns) do
    ~STAR"""
    <.columns>
      <:column>One</:column>
      <:column>Two</:column>
    </.columns>
    """
  end

  slot(:column)

  def columns(assigns) do
    ~STAR"""
    <section id="columns">{render_slot(@column)}</section>
    """
  end
end
