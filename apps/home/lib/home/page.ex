defmodule Home.Page do
  require Logger
  require OK
  use OK.Pipe

  defstruct orig: nil, html: nil, info: nil, tocs: []

  @typedoc """
  A displayable page in the web app. May be produced from a number of different
  source formats, currently including:

  - HTML
  - Markdown (with site-local extensions)

  ## Fields

  - `orig`: The source loaded directly from disk.
  - `html`: Rendered HTML ready to be injected into a template.
  - `info`: Structured metadata extracted from the frontmatter.
  - `tocs`: A tree of headings provided by the Markdown parser.
  """
  @type t :: %__MODULE__{
          orig: Wyz.Document.t() | Wyz.File.t(),
          html: String.t() | nil,
          info: __MODULE__.Metadata.t() | nil,
          tocs: [Wyz.Markdown.Toc.t()]
        }

  @typedoc """
  Supported source files for Pages
  """
  @type s :: :html | :markdown

  @doc """
  Loads a page out of the page-root. Can only be used on
  Markdown-with-frontmatter or HTML files.
  """
  @spec load_page(
          String.t() | [String.t()],
          Path.t() | nil
        ) :: {:ok, __MODULE__.t()} | {:error, any()}
  def load_page(path, site_root \\ nil)
  def load_page(path, site_root) when is_binary(path), do: load_page([path], site_root)

  def load_page(path, site_root) when is_list(path) do
    path
    |> lookup(site_root || Home.site_root())
    |> resolve()
  end

  @doc """
  Renders a loaded document into HTML. The output of this function is a Page
  with its `.html` field filled in.

  Pages loaded from HTML files are already shown; Pages loaded from Markdown
  files are run through the Markdown processor to produce an HTML string.
  """
  @spec show(__MODULE__.t() | {:file, Path.t()}) :: {:ok, __MODULE__.t()} | {:error, term()}
  def show(this)
  def show(%__MODULE__{orig: %Wyz.File{}} = this), do: {:ok, this}

  def show(%__MODULE__{orig: %Wyz.Document{} = doc} = this) do
    OK.for do
      {html, tocs} <- Wyz.Markdown.render(doc, 2..3)
    after
      %__MODULE__{this | html: html, tocs: tocs}
    end
  end

  def show({:file, path}), do: {:ok, {:file, path}}

  @doc """
  Attempts to discover the page title. This is always known from Markdown
  documents, and is either the `<title>` or first `<h1>` element in HTML
  documents.
  """
  @spec get_title(__MODULE__.t()) :: {:ok, String.t()} | {:error, :no_title}
  def get_title(page)

  def get_title(%__MODULE__{orig: %Wyz.Document{}, info: info}),
    do: {:ok, info.page_title || info.title}

  def get_title(%__MODULE__{orig: %Wyz.File{}, html: html}) do
    OK.for do
      ast <- Floki.parse_document(html)
      title = Floki.find(ast, "title")
      h1s = Floki.find(ast, "h1")
    after
      case Enum.concat(title, h1s) |> Enum.take(1) |> Enum.map(&Wyz.Markdown.text_contents/1) do
        [show] -> {:ok, Enum.join(show, " ")}
        [] -> {:error, :no_title}
      end
    end
  end

  # Receives a list of path fragments and a root directory, and produces a set
  # of format and filenames which may satisfy the request.
  @spec lookup([String.t()], Path.t() | nil) :: [{__MODULE__.s(), Path.t()}]
  defp lookup(path, site_root) when is_list(path) do
    full_path =
      [site_root || Home.site_root() | path]
      |> Path.join()

    case Path.extname(full_path) do
      ".html" ->
        [{:html, full_path}]

      ".md" ->
        [{:markdown, full_path}]

      "" ->
        [
          {:html, "#{full_path}.html"},
          {:markdown, "#{full_path}.md"},
          {:html, Path.join(full_path, "index.html")},
          {:markdown, Path.join(full_path, "index.md")},
          {:markdown, Path.join(full_path, "README.md")}
        ]

      asset ->
        [{:asset, full_path}]
    end
  end

  # Given a collection of format and filepaths, attempt to load each in turn
  # until one succeeds
  @spec resolve([{__MODULE__.s(), Path.t()}]) ::
          {:ok, __MODULE__.t() | {:file, Path.t()}} | {:error, :enoent | term()}
  defp resolve(paths) when is_list(paths) do
    paths
    |> Stream.filter(fn {_key, val} -> File.exists?(val) end)
    |> Stream.map(&load/1)
    |> Stream.filter(fn
      {:ok, _} ->
        true

      {:error, _} ->
        false
    end)
    |> Stream.take(1)
    |> Enum.to_list()
    |> List.first({:error, :enoent})
  end

  # Given a format and filepath, attempt to load the file into the appropriate
  # container.
  @spec load({__MODULE__.s(), Path.t()}) ::
          {:ok, __MODULE__.t() | {:file, Path.t()}} | {:error, :enoent | term()}
  defp load(format_and_path)

  defp load({:asset, asset_path}), do: {:ok, {:file, asset_path}}

  defp load({:html, html_path}) do
    # Logger.info("loading HTML from #{html_path}")
    html_path |> Wyz.File.load() ~>> from_html()
  end

  defp load({:markdown, markdown_path}) do
    # Logger.info("loading Markdown from #{markdown_path}")
    markdown_path |> Wyz.Document.load() ~>> from_markdown()
  end

  defp load({kind, nil}) do
    Logger.error("Loading #{kind} from nowhere!")
    {:error, :enoent}
  end

  defp load({kind, path}) do
    Logger.error("Unsupported source file `#{kind}` at `#{path}`")
    {:error, :invalid_source_kind}
  end

  @spec from_html(Wyz.File.t()) :: {:ok, __MODULE__.t()}
  defp from_html(%Wyz.File{data: html} = file) do
    OK.try do
      parsed <- Floki.parse_document(html)
      info <- __MODULE__.Metadata.from_html(parsed)
    after
      {:ok, %__MODULE__{orig: file, html: html, info: info}}
    rescue
      _ -> {:ok, %__MODULE__{orig: file, html: html}}
    end
  end

  @spec from_markdown(Wyz.Document.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  defp from_markdown(%Wyz.Document{} = doc) do
    doc
    |> __MODULE__.Metadata.update_document()
    ~> (&%__MODULE__{orig: &1, info: &1.meta}).()
  end
end
