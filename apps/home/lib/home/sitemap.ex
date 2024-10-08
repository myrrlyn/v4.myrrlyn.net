defmodule Home.Sitemap do
  require OK
  require Logger
  use OK.Pipe

  @type dirent ::
          {:file, String.t()}
          | {:dir, String.t(), [__MODULE__.dirent()]}
          | {:symlink, String.t(), Path.t()}

  @doc """
  Emits a structured tree of the site contents.
  """
  def sitemap(opts \\ []) do
    root = Keyword.get(opts, :root, "/")
    {:dir, root, ls_r(Path.join(Home.site_root(), root))}
  end

  @doc """
  Transforms the sitemap into an Earmark AST.
  """
  def sitenav(opts \\ []) do
    {:dir, "/", pages} = sitemap(opts)
    {{:dir, "blog", blog_pages}, pages} = List.keytake(pages, "blog", 1)
    {{:dir, "oeuvre", oeuvre_pages}, pages} = List.keytake(pages, "oeuvre", 1)

    opts = Keyword.update(opts, :group, "~", & &1)

    make_ulli([
      to_ast({:dir, "/", pages}, "/", [{:show, "Main Site"} | opts]),
      to_ast({:dir, "blog", blog_pages}, "/", [{:show, "Blog"} | opts]),
      to_ast({:dir, "oeuvre", oeuvre_pages}, "/", [{:show, "TES Writing"} | opts])
    ])
  end

  @doc """
  Enumerates directory contents that are useful for the site.

  Only shows HTML or Markdown files, removes dotfiles, README, and licenses.
  """
  def ls(path) do
    OK.for do
      items <- File.ls(path)
    after
      items
      |> Stream.filter(fn p -> Path.extname(p) in [".html", ".md", ""] end)
      |> Stream.reject(fn p -> String.starts_with?(p, ".") end)
      |> Stream.reject(fn p -> p in ["README.md", "LICENSE.txt"] end)
      |> Stream.reject(&hide_from_sitemap(&1, path))
      |> Enum.sort()
    end
  end

  @spec ls_r(Path.t()) :: [__MODULE__.dirent()]
  def ls_r(path)

  def ls_r(path) do
    case ls(path) do
      {:ok, c} -> c
      {:error, _} -> []
    end
    |> Enum.map(fn item ->
      full = Path.join(path, item)

      cond do
        (
          {status, out} = File.read_link(full)
          status == :ok
        ) ->
          {:symlink, item, out}

        File.regular?(full) ->
          {:file, item}

        File.dir?(full) ->
          {:dir, item, ls_r(full)}
      end
    end)
  end

  @spec to_ast(__MODULE__.dirent(), Path.t(), Keyword.t()) :: Earmark.ast_tuple() | nil
  def to_ast(item, dir, opts \\ [])
  def to_ast({:symlink, _, _}, _, _), do: nil

  def to_ast({:file, name}, dir, opts) do
    full = Path.join(dir, name)

    url =
      full
      |> String.replace(Home.site_root(), "")
      |> String.replace(~r/\/[0-9-]{11}/, "/")
      |> String.replace(~r/(index|README)?\.(md|html)$/, "")

    case get_title_for(name, dir) do
      {:ok, title} ->
        file_as_ast(title, url, opts)

      {:error, :unsupported} ->
        "<Untitled>"

      {:error, error} ->
        {"span", [{"class", "error"}],
         [Path.join(dir, name), ": ", [{"code", [], [inspect(error)], %{}}]], %{}}
    end
  end

  def to_ast({:dir, dir = "blog", categories}, "/", opts) do
    {show, opts} = List.keytake(opts, :show, 0) || {nil, opts}

    blogname =
      with nil <- show, {:error, _} <- get_title_for("index.md", dir) do
        "Blog"
      else
        {:show, name} -> name
        {:ok, name} -> name
        name -> name
      end

    {{:group, group}, opts} = List.keytake(opts, :group, 0) || {{:group, nil}, opts}

    categories =
      categories
      |> Enum.map(fn
        {:dir, cpath, articles} ->
          cpath_full = Path.join(Home.blog_root(), cpath)

          articles =
            articles
            |> Enum.reject(fn
              {:file, "index.md"} ->
                true

              {:file, name} ->
                case Home.Page.load_page(name, cpath_full) do
                  {:ok, page} -> !page.info.published
                  {:error, _} -> true
                end

              {:dir, _, _} ->
                true

              {:symlink, _, _} ->
                true

              _ ->
                true
            end)
            |> Enum.map(fn {:file, fname} ->
              aname =
                case get_title_for(fname, cpath_full) do
                  {:ok, n} -> n
                  {:error, _} -> show_slug(fname)
                end

              {:file, fname}
            end)

          {:dir, cpath, articles}

        {:file, _} ->
          nil
      end)
      |> Enum.reject(fn
        nil -> true
        _ -> false
      end)

    dir_as_ast(blogname, "/blog", categories, [{:group, group} | opts])
  end

  def to_ast({:dir, dir, children}, parent, opts) do
    path = Path.join(parent, dir)

    {show, opts} = List.keytake(opts, :show, 0) || {nil, opts}

    dirname =
      with nil <- show,
           {:error, _} <- get_title_for("index.md", dir),
           {:error, _} <- get_title_for("README.md", dir) do
        dir |> String.split(~r/[_-]/) |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
      else
        {:show, name} -> name
        {:ok, name} -> name
        name -> name
      end

    dir_as_ast(
      dirname,
      String.replace(path, Home.site_root(), ""),
      children
      # No empty directories
      |> Stream.reject(fn
        {:dir, _, []} -> true
        _ -> false
      end)
      # No index/README files
      |> Stream.reject(fn
        {:file, name} -> name in ["index.md", "README.md"]
        _ -> false
      end)
      |> Stream.reject(&(&1 == nil))
      |> Enum.to_list(),
      opts
    )
  end

  def get_title_for(name, dir) do
    if Path.extname(name) in [".html", ".md"] do
      dir
      |> Path.join(name)
      |> Path.relative_to(Home.site_root())
      |> Path.split()
      |> Home.Page.load_page(Home.site_root())
      ~>> Home.Page.get_title()
    else
      {:error, :unsupported}
    end
  end

  def hide_from_sitemap(name, dir) do
    OK.try do
      page <- Home.Page.load_page([name], dir)
    after
      case page do
        %Home.Page{info: %Home.Page.Metadata{} = info} ->
          !info.published

        %Home.Page{orig: %Wyz.File{}, html: html} ->
          case html
               |> Floki.parse_document()
               ~> Floki.find("meta[name=\"wyz-published\"]") do
            {:ok, "0"} -> false
            _ -> true
          end

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  def dir_as_ast(name, url, children, opts \\ []) do
    parent = Path.dirname(url)

    {{:group, group}, opts} = List.keytake(opts, :group, 0) || {{:group, nil}, opts}

    attrs =
      cond do
        group != nil -> [{"name", group}]
        url != "/" -> [{"name", parent}]
        true -> []
      end

    aria = aria_nav(url, opts)

    attrs =
      case aria do
        [{_, _}] -> [{"open", "1"} | attrs]
        [] -> attrs
        _ -> attrs
      end

    show =
      case Home.Page.load_page(url) do
        {:ok, page} -> [{"a", [{"href", url}], [name], %{}}]
        {:error, :enoent} -> [name]
      end

    {"details", attrs,
     [
       {"summary", aria, show, %{}},
       children |> Enum.map(&to_ast(&1, url, opts)) |> make_ulli()
     ], %{}}
  end

  def file_as_ast(name, url, opts \\ []) do
    url = Path.rootname(url)
    {"span", aria_nav(url, opts), [{"a", [{"href", url}], [name], %{}}], %{}}
  end

  def make_ulli(items),
    do: {"ul", [{"class", "nav"}], items |> Enum.map(&{"li", [], [&1], %{}}), %{}}

  def show_slug(slug) do
    slug
    # Remove leading date
    |> String.replace(~r/^[0-9-]{11}/, "")
    # Split between words
    |> String.split("-")
    # Capitalize each
    |> Enum.map(&String.capitalize/1)
    # Recompose
    |> Enum.join(" ")
  end

  def aria_nav(url, opts) do
    at = Keyword.get(opts, :at, "/")

    cond do
      at == url -> [{"aria-current", "page"}]
      String.starts_with?(at, "/blog") and url == "/" -> []
      String.starts_with?(at, "/oeuvre") and url == "/" -> []
      String.starts_with?(at, url) -> [{"aria-current", "step"}]
      true -> []
    end
  end
end
