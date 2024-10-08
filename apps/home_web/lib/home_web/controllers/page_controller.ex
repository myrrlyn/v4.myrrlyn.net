defmodule HomeWeb.PageController do
  use HomeWeb, :controller

  require Logger
  require OK
  use OK.Pipe

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def show_page(conn, %{"path" => ["html-sample"]} = params) do
    Logger.info("showing html-sample")

    conn
    |> assign(:template, :plain)
    |> assign(:classes, ["no-counters"])
    |> show_page(%{params | "path" => ["html-sample.html"]})
  end

  def show_page(conn, %{"path" => path} = params) do
    OK.try do
      page <- path |> Home.Page.load_page() ~>> Home.Page.show()
    after
      conn |> assign(:slug, Path.join(["/" | path])) |> show_page(page)
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

  def error(conn, opts \\ []) do
    status = Keyword.get(opts, :status, 404)

    conn
    |> put_status(status)
    |> put_view(HomeWeb.ErrorHTML)
    |> render(Keyword.get(opts, :template, "#{status}.html"),
      message: Keyword.get(opts, :message)
    )
  end
end
