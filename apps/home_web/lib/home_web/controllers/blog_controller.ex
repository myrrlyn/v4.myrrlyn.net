defmodule HomeWeb.BlogController do
  use HomeWeb, :controller
  require Logger
  require OK
  use OK.Pipe

  def load(
        conn,
        %{"category" => category, "article" => article, "resource" => resource} = params
      ) do
    conn |> send_file(200, Path.join([Home.site_root(), "blog", category, article, resource]))
  end

  def load(conn, %{"category" => category, "article" => article} = params) do
    slug = Path.join(["/blog", category, article])

    case [Home.site_root(), "blog", category]
         |> Path.join()
         |> Home.Sitemap.ls()
         ~> Enum.filter(fn
           name ->
             Regex.match?(~r/^[0-9-]{11}#{article}.md$/, name)
         end)
         ~> List.first() do
      {:error, err} ->
        conn
        |> HomeWeb.PageController.error(status: 403, message: err)

      {:ok, nil} ->
        Logger.error("could ls, couldn't locate file")
        conn |> HomeWeb.PageController.error(status: 404, message: :no_such_file)

      {:ok, name} ->
        OK.try do
          page <- [category, name] |> Home.Page.load_page(Home.blog_root()) ~>> Home.Page.show()
        after
          conn
          |> assign(:slug, slug)
          |> put_view(HomeWeb.PageHTML)
          |> HomeWeb.PageController.show_page(page)
        rescue
          err ->
            conn
            |> put_view(HomeWeb.ErrorHTML)
            |> HomeWeb.PageController.error(status: 404, message: err)
        end
    end
  end
end
