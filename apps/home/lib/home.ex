defmodule Home do
  @moduledoc """
  Home keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # The default file-system root in which to search for relative paths. Can be
  # overridden by setting `config :home, Home, site_root: "/path/to/pages"`
  @site_root Path.join("priv", "pages")

  @doc """
  Gets the path to the root of displayable pages.
  """
  @spec site_root() :: Path.t()
  def site_root(),
    do: Application.get_env(:home, __MODULE__, []) |> Keyword.get(:site_root, @site_root)

  def blog_root(), do: Path.join(site_root(), "blog")

  def oeuvre_root(), do: Path.join(site_root(), "oeuvre")
end
