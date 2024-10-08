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
      conn
      |> put_flash(:error, "this site is under construction")
      |> assign(:classes, ["theme-ansi" | conn.assigns[:classes] || []])
      |> render(conn.assigns[:template] || :page,
        html: page.html,
        info: page.info,
        tocs: page.tocs
      )
    rescue
      error ->
        conn
        |> put_status(403)
        |> put_view(HomeWeb.ErrorHTML)
        |> render("403.html", message: error)
    end
  end
end
