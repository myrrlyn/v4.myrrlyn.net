defmodule Home.Page do
  require Logger
  require OK
  use OK.Pipe

  # The default file-system root in which to search for relative paths. Can be
  # overridden by setting `config :home, Home.Page, page_root: "/path/to/pages"`
  @page_root Path.join("priv", "pages")

  defstruct orig: nil, html: nil

  @doc """
  Loads a page out of the page-root. Can only be used on
  Markdown-with-frontmatter files.
  """
  @spec load_page(Path.t()) :: {:ok, Wyz.Document.t()} | {:error, any()}
  def load_page(path) when is_binary(path) do
    path
    |> make_page_path()
    |> Wyz.Document.load()
    ~>> from_document()
  end

  @doc """
  Renders a loaded document into HTML.
  """
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

  defp from_document(%Wyz.Document{} = doc) do
    OK.for do
      orig <- doc |> __MODULE__.Metadata.update_document()
    after
      %__MODULE__{orig: orig}
    end
  end

  defp make_page_path(path) when is_binary(path) do
    Application.get_env(:home, __MODULE__)
    |> Keyword.get(:page_root, @page_root)
    |> Path.join(path)
  end
end
