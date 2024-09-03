defmodule HomeWeb.PageController do
  use HomeWeb, :controller

  require Logger
  require OK

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def show_page(conn, %{"path" => path} = params) do
    path = Path.join(path)

    path = case Path.extname(path) do
      "" -> {:ok, "#{path}.md"}
      ".md" -> {:ok, path}
      _ -> {:error, "non-Markdown pages are not yet supported"}
    end

    with {:ok, path} <- path,
    {:ok, page} <- Home.Page.load_page(path),
    {:ok, page} <- Home.Page.show(page) do
      conn |> render(:page, page: page)
    else
      {:error, error} ->
        conn
        |> put_status(403)
        |> put_view(HomeWeb.ErrorHTML)
        |> render("403.html", message: error)
    end

  end
end
