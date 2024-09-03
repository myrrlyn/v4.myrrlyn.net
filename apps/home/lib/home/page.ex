defmodule Home.Page do
  require OK
  use OK.Pipe

  # The default file-system root in which to search for relative paths. Can be
  # overridden by setting `config :home, Home.Page, page_root: "/path/to/pages"`
  @page_root Path.join("priv", "pages")

  defstruct orig: nil, html: nil

  @doc """
  Loads a page out of `priv/pages/`. Can only be used on
  Markdown-with-frontmatter files.
  """
  @spec load_page(Path.t()) :: {:ok, Wyz.Document.t()} | {:error, any()}
  def load_page(path) when is_binary(path) do
    path
    |> make_page_path()
    |> Wyz.Document.load()
    ~>> Home.Page.Metadata.update_document()
    # TODO(myrrlyn): Wrap in local structure
  end

  @doc """
  Renders a loaded document into HTML.
  """
  def show(%Wyz.Document{text: {_head, body}} = this) do
    case EarmarkParser.as_ast(body) do
      {status, ast, messages} -> {status, {ast, messages}}
    end
    ~>> (fn {ast, _messages} ->
           {:ok, %__MODULE__{orig: this, html: Earmark.Transform.transform(ast)}}
         end).()
  end

  defp make_page_path(path) when is_binary(path) do
    Application.get_env(:home, __MODULE__)
    |> Keyword.get(:page_root, @page_root)
    |> Path.join(path)
  end
end
