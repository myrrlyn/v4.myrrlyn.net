defmodule HomeWeb.PageController do
  use HomeWeb, :controller

  require Logger
  require OK
  use OK.Pipe

  def show_page(conn, %{"path" => ["html-sample"]} = params) do
    Logger.info("showing html-sample")

    conn
    |> assign(:template, :plain)
    |> assign(:classes, ["no-counters"])
    |> show_page(%{params | "path" => ["html-sample.html"]})
  end

  def show_page(conn, %{"path" => path}) do
    OK.try do
      page <- path |> Home.Page.load_page() ~>> Home.Page.show()
    after
      conn
      |> assign(:slug, Path.join(["/" | path]))
      |> show_page(page)
    rescue
      err -> error(conn, status: 403, message: err)
    end
  end

  def show_page(conn, %Home.Page{} = page) do
    conn
    |> put_flash(:error, "this site is under construction")
    |> assign(:classes, ["theme-ansi" | conn.assigns[:classes] || []])
    |> render(conn.assigns[:template] || :page,
      html: page.html,
      info: page.info,
      tocs: page.tocs
    )
  end

  def show_page(conn, {:file, path}) do
    conn |> put_resp_content_type(MIME.from_path(path)) |> send_file(200, path)
  end

  def show_blog(
        conn,
        %{"category" => category, "article" => article, "resource" => resource} = params
      ) do
    conn |> send_file(200, Path.join([Home.site_root(), "blog", category, article, resource]))
  end

  def show_blog(conn, %{"category" => category, "article" => article} = params) do
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
        |> error(status: 403, message: err)

      {:ok, nil} ->
        Logger.error("could ls, couldn't locate file")
        conn |> error(status: 404, message: :no_such_file)

      {:ok, name} ->
        OK.try do
          page <- [category, name] |> Home.Page.load_page(Home.blog_root()) ~>> Home.Page.show()
        after
          conn
          |> assign(:slug, slug)
          |> show_page(page)
        rescue
          err ->
            conn
            |> put_view(HomeWeb.ErrorHTML)
            |> error(status: 404, message: err)
        end
    end
  end

  def error(conn, opts \\ []) do
    status = Keyword.get(opts, :status, 404)

    conn
    |> put_status(status)
    |> put_view(HomeWeb.ErrorHTML)
    |> render(Keyword.get(opts, :template, "#{status}.html"),
      message: Keyword.get(opts, :message),
      page_title: "Error"
    )
  end
end
