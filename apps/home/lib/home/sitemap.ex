defmodule Home.Sitemap do
  require OK
  require Logger
  use OK.Pipe

  @subroots ["blog", "oeuvre"]

  @type dirent ::
          {:file, String.t()}
          | {:dir, String.t(), [__MODULE__.dirent()]}
          | {:symlink, String.t(), String.t()}

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
    root = Keyword.get(opts, :root, "/")
    sitemap(opts) |> to_ast(root, opts)
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
  def to_ast({:symlink, _, _}, _, opts), do: nil

  def to_ast({:file, name}, dir, opts) do
    full = Path.join(dir, name)

    url =
      full
      |> String.replace(Home.site_root(), "")
      |> String.replace(~r/(index|README)?\.(md|html)$/, "")

    case get_title_for(name, dir) do
      {:ok, title} ->
        file_as_ast(title, url, opts)

      {:error, :unsupported} ->
        nil

      {:error, error} ->
        {"span", [{"class", "error"}],
         [Path.join(dir, name), ": ", [{"code", [], [inspect(error)], %{}}]], %{}}
    end
  end

  def to_ast({:dir, "blog", categories}, parent, opts) do
    blogname =
      case get_title_for("index.md", "blog") do
        {:ok, n} -> n
        {:error, _} -> "Blog"
      end

    categories =
      categories
      |> Enum.map(fn
        {:dir, cpath, articles} ->
          cpath_full = Path.join([Home.site_root(), "blog", cpath])

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

              file_as_ast(
                aname,
                Path.join(["/blog", cpath, String.replace(fname, ~r/^[0-9-]{11}/, "")])
              )
            end)

          cat_name =
            case get_title_for("index.md", Path.join([Home.site_root(), "blog", cpath])) do
              {:ok, n} -> n
              {:error, _} -> show_slug(cpath)
            end

          dir_as_ast(cat_name, Path.join("/blog", cpath), articles, opts)

        {:file, _} ->
          nil
      end)
      |> Enum.reject(fn
        nil -> true
        _ -> false
      end)

    dir_as_ast("Blog", "/blog", categories, opts)
  end

  def to_ast({:dir, dir, children}, parent, opts) do
    path = Path.join(parent, dir)

    case children
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
         |> Enum.to_list() do
      [] ->
        nil

      c ->
        show =
          case dir do
            "/" -> "~myrrlyn/"
            _ -> nil
          end

        dirname =
          with nil <- show,
               {:error, _} <- get_title_for("index.md", dir),
               {:error, _} <- get_title_for("README.md", dir) do
            dir |> String.split(~r/[_-]/) |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
          else
            {:ok, name} -> name
            name -> name
          end

        dir_as_ast(
          dirname,
          String.replace(path, Home.site_root(), ""),
          c
          |> Stream.map(&to_ast(&1, path, opts))
          |> Stream.reject(fn v -> v == nil end)
          |> Stream.map(fn n -> {"li", [], n, %{}} end)
          |> Enum.to_list(),
          opts
        )
    end
  end

  # def get_title_for("index.md", dir), do: {:ok, dir |> reseat() |> Path.basename()}
  # def get_title_for("README.md", dir), do: {:ok, dir |> reseat() |> Path.basename()}

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
        %Home.Page{orig: %Wyz.Document{}, info: info} ->
          !info.published

        %Home.Page{orig: %Wyz.File{}, html: html} ->
          case html
               |> Floki.parse_document()
               ~> Floki.find("meta[name=\"myrrlyn-hide-sitemap\"]") do
            {:ok, nil} -> false
            {:ok, _} -> true
            _ -> false
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

    at = Keyword.get(opts, :at, "/")

    attrs =
      if url != "/" do
        [{"name", parent}]
      else
        []
      end

    attrs =
      if String.starts_with?(at, url) do
        [{"open", "1"} | attrs]
      else
        attrs
      end

    {"details", attrs,
     [
       {"summary", [], [{"a", [{"href", url}], [name], %{}}], %{}},
       {"ul", [{"class", "nav"}], Enum.map(children, fn c -> {"li", [], [c], %{}} end), %{}}
     ], %{}}
  end

  def file_as_ast(name, url, opts \\ []) do
    curr =
      if url == Keyword.get(opts, :at) do
        [{"aria-current", "page"}]
      else
        []
      end

    {"a", [{"href", Path.rootname(url)} | curr], [name], %{}}
  end

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

  def reseat(dir), do: dir |> String.replace(Home.site_root(), "~myrrlyn")
end
