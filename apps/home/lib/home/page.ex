defmodule Home.Page do
  require Logger
  require OK
  use OK.Pipe

  # The default file-system root in which to search for relative paths. Can be
  # overridden by setting `config :home, Home.Page, page_root: "/path/to/pages"`
  @page_root Path.join("priv", "pages")

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
  @spec load_page([String.t()], Path.t()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def load_page(path, page_root \\ @page_root) when is_list(path) and is_binary(page_root) do
    path
    |> lookup(page_root)
    |> resolve()
  end

  @doc """
  Renders a loaded document into HTML. The output of this function is a Page
  with its `.html` field filled in.

  Pages loaded from HTML files are already shown; Pages loaded from Markdown
  files are run through the Markdown processor to produce an HTML string.
  """
  @spec show(__MODULE__.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  def show(this)
  def show(%__MODULE__{orig: %Wyz.File{}} = this), do: {:ok, this}

  def show(%__MODULE__{orig: %Wyz.Document{} = doc} = this) do
    OK.for do
      {html, tocs} <- Wyz.Markdown.render(doc, 2..3)
    after
      %__MODULE__{this | html: html, tocs: tocs}
    end
  end

  # Receives a list of path fragments and a root directory, and produces a set
  # of format and filenames which may satisfy the request.
  @spec lookup([String.t()], Path.t()) :: [{__MODULE__.s(), Path.t()}]
  defp lookup(path, page_root) when is_list(path) and is_binary(page_root) do
    full_path =
      Application.get_env(:home, __MODULE__)
      |> Keyword.get(:page_root, page_root)
      |> Path.join(path)

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
    end
  end

  # Given a collection of format and filepaths, attempt to load each in turn
  # until one succeeds
  @spec resolve([{__MODULE__.s(), Path.t()}]) ::
          {:ok, __MODULE__.t()} | {:error, :enoent | term()}
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
    |> Stream.concat([{:error, :enoent}])
    |> Enum.to_list()
    |> List.first()
  end

  # Given a format and filepath, attempt to load the file into the appropriate
  # container.
  @spec load({__MODULE__.s(), Path.t()}) :: {:ok, __MODULE__.t()} | {:error, :enoent | term()}
  defp load(format_and_path)

  defp load({:html, html_path}) do
    Logger.info("loading HTTML from #{html_path}")
    html_path |> Wyz.File.load() ~>> from_html()
  end

  defp load({:markdown, markdown_path}) do
    Logger.info("loading Markdown from #{markdown_path}")
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
  defp from_html(%Wyz.File{data: html} = file), do: {:ok, %__MODULE__{orig: file, html: html}}

  @spec from_markdown(Wyz.Document.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  defp from_markdown(%Wyz.Document{} = doc) do
    doc
    |> __MODULE__.Metadata.update_document()
    ~> (&%__MODULE__{orig: &1, info: &1.meta}).()
  end
end
