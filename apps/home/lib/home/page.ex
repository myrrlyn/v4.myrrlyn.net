defmodule Home.Page do
  require Logger
  require OK
  use OK.Pipe

  # The default file-system root in which to search for relative paths. Can be
  # overridden by setting `config :home, Home.Page, page_root: "/path/to/pages"`
  @page_root Path.join("priv", "pages")

  defstruct orig: nil, html: nil, info: nil

  @typedoc """
  A displayable page in the web app. May be produced from a number of different
  source formats, currently including:

  - HTML
  - Markdown (with site-local extensions)

  ## Fields

  - `orig`: The source loaded directly from disk.
  - `html`: Rendered HTML ready to be injected into a template.
  - `meta`:
  """
  @type t :: %__MODULE__{
          orig: Wyz.Document.t() | Wyz.File.t(),
          html: String.t() | nil,
          info: Wyz.Document.Metadata.t() | nil
        }

  @doc """
  Loads a page out of the page-root. Can only be used on
  Markdown-with-frontmatter files.
  """
  @spec load_page([String.t()]) :: {:ok, Wyz.Document.t() | Wyz.File.t()} | {:error, any()}
  def load_page(path, page_root \\ @page_root) when is_list(path) do
    path
    |> lookup(page_root)
    |> resolve()
  end

  @doc """
  Renders a loaded document into HTML.
  """
  def show(this)
  def show(%__MODULE__{orig: %Wyz.File{}} = this), do: {:ok, this}

  def show(%__MODULE__{orig: %Wyz.Document{text: {_head, body}}} = this) do
    OK.for do
      {status, ast, messages} = EarmarkParser.as_ast(body)
      {ast, messages} <- {status, {ast, messages}}
      html = Earmark.Transform.transform(ast)
    after
      for message <- messages do
        Logger.warning("Earmark parse message: #{message}")
      end

      %__MODULE__{this | html: html}
    end
  end

  defp from_html(%Wyz.File{data: html} = file), do: {:ok, %__MODULE__{orig: file, html: html}}

  defp from_markdown(%Wyz.Document{} = doc) do
    doc
    |> __MODULE__.Metadata.update_document()
    ~> (&%__MODULE__{orig: &1, info: &1.meta}).()
  end

  @spec lookup([String.t()], Path.t()) :: Keyword.t()
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
          {:html, "#{full_path}/index.html"},
          {:markdown, "#{full_path}/index.md"},
          {:markdown, "#{full_path}/README.md"}
        ]
    end
  end

  defp resolve(paths) when is_list(paths) do
    case paths
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
         |> List.first() do
      nil ->
        {:error, :enoent}

      {:ok, value} ->
        {:ok, value}
    end
  end

  defp load({:html, html_path}) do
    Logger.info("loading HTTML from #{html_path}")
    html_path |> Wyz.File.load() ~>> from_html()
  end

  defp load({:markdown, markdown_path}) do
    Logger.info("loading Markdown from #{markdown_path}")

    markdown_path
    |> Wyz.Document.load()
    ~>> from_markdown()
    |> (fn
          {:ok, val} ->
            {:ok, val}

          {:error, error} ->
            {:error, error}

          other ->
            Logger.info("load :md, #{inspect(other)}")
            {:ok, other}
        end).()
  end

  defp load({kind, nil}) do
    Logger.error("Loading #{kind} from nowhere!")
    {:error, :enoent}
  end
end
