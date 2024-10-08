defmodule Wyz.Markdown do
  @moduledoc """
  Processes and renders Markdown documents into HTML.

  I extend the [Earmark] parser using its IAL syntax in order to support
  production of semantic HTML. As such, I require additional processing of the
  Earmark AST before emitting the HTML string used by a site front-end.

  This module is capable of:

  - generating a table of contents from HTML heading elements
  - generating unique identifiers for in-document link targets
  - other transforms as needed

  [Earmark]: https://hexdocs.pm/earmark
  """

  require Logger
  require OK
  use OK.Pipe

  @typedoc """
  A table of contents corresponding to the document headings.
  """
  @type toc :: __MODULE__.Toc.t()

  @opts_earmark %Earmark.Options{
    compact_output: true,
    eex: true,
    breaks: false,
    code_class_prefix: "lang- language-",
    footnotes: true,
    gfm_tables: true,
    sub_sup: true
  }

  def render!(source) do
    case render(source) do
      {:ok, out} -> out
      {:error, {_, err}} -> raise Earmark.Error, inspect(err)
    end
  end

  @doc """
  Produces an HTML string for a Markdown document.

  ## Parameters

  1. A `Wyz.Document` structure, whose main body will be rendered as HTML
  2. A filter of which headings to retain in the produced table of contents.

  ## Returns

  - `{:ok, {html, tocs}}`: an HTML string and a maybe-nested ordered list of
    headings
  - `{:error, {html, messages}}`: an HTML string and a list of diagnostics. The
    HTML string is Earmark's best effort at processing the input, and we make
    no guarantees about its contents.
  """
  @spec render(Wyz.Document.t() | String.t(), Range.t(1, 6)) ::
          {:ok, {String.t(), __MODULE__.toc()}} | {:error, term()}
  def render(doc, keep_headings \\ 1..6)

  def render(%Wyz.Document{} = doc, keep_headings) do
    OK.for do
      %Wyz.Document{text: {_, body}} <- Wyz.Document.parse_frontmatter_yaml(doc)
    after
      render(body, keep_headings)
    end
  end

  def render(text, keep_headings) when is_binary(text) do
    OK.try do
      idents =
        case __MODULE__.Idents.start_link() do
          {:ok, agent} -> agent
          {:error, {:already_started, agent}} -> agent
          {:error, _} -> nil
        end

      {status, output, messages} =
        Earmark.Parser.as_ast(text, @opts_earmark)

      {ast, messages} <- {status, {output, messages}}
      ast = Earmark.Transform.map_ast(ast, &__MODULE__.walk_ast(&1, idents))
      tocs = Task.async(fn -> __MODULE__.Toc.read_ast(ast, keep_headings) end)
      html = Task.async(fn -> Earmark.Transform.transform(ast, @opts_earmark) end)
    after
      for message <- messages do
        case message do
          {:deprecated, _, msg} ->
            Logger.warning("Earmark deprecation: #{msg}")

          {other, level, msg} ->
            Logger.warning("#{other}: #{level}: #{msg}")
        end
      end

      tocs = Task.await(tocs)
      html = Task.await(html)

      if idents, do: __MODULE__.Idents.stop(idents)

      {:ok, {html, tocs}}
    rescue
      {:error, {ast, messages}} ->
        {:error, {Earmark.Transform.transform(ast, @opts_earmark), messages}}
    end
  end

  @doc """
  Transform function invoked by `&Earmark.Parser.map_ast/2`. Must take and
  return an Earmark AST tuple.
  """
  @spec walk_ast(Earmark.ast_node(), pid() | nil) :: Earmark.ast_node()
  def walk_ast(node, idents \\ nil)

  def walk_ast({"h2", _, _, _} = node, idents), do: identify(node, idents)
  def walk_ast({"h3", _, _, _} = node, idents), do: identify(node, idents)
  def walk_ast({"h4", _, _, _} = node, idents), do: identify(node, idents)
  def walk_ast({"h5", _, _, _} = node, idents), do: identify(node, idents)
  def walk_ast({"h6", _, _, _} = node, idents), do: identify(node, idents)

  def walk_ast({_, attrs, inner, meta} = node, _) do
    case List.keytake(attrs, "tag", 0) do
      {{"tag", tag}, rest} -> {tag, rest, inner, meta}
      _ -> node
    end
  end

  def walk_ast(node, _), do: node

  @doc """
  Attaches an `id` attribute to a DOM node.

  If one is present, it is retained; otherwise, it is generated from the text
  contents of the node.
  """
  @spec identify(Earmark.ast_tuple(), pid() | nil) :: Earmark.ast_tuple()
  def identify({tag, attrs, inner, meta}, idents \\ nil) do
    {id, rest} =
      case List.keytake(attrs, "id", 0) do
        nil ->
          id = inner |> text_contents() |> Enum.join(" ") |> to_ident()
          {id, attrs}

        {{"id", id}, rest} ->
          {id, rest}
      end

    {tag,
     case id do
       "" -> rest
       id -> [{"id", __MODULE__.Idents.identify(idents, id)} | rest]
     end, inner, meta}
  end

  @doc """
  Produces a list of strings containing only the plaintext contents of a DOM
  subtree.
  """
  @spec text_contents(Earmark.ast() | Floki.html_tree()) :: [String.t()]
  def text_contents(ast)
  def text_contents(text) when is_binary(text), do: [text]
  def text_contents({_, _, inner}), do: text_contents(inner)
  def text_contents({_, _, inner, _}), do: text_contents(inner)

  def text_contents(ast) when is_list(ast),
    do: ast |> Stream.flat_map(&text_contents/1)

  @doc """
  Converts a string to kebab-case suitable for use as a URL fragment.
  """
  @spec to_ident(String.t()) :: String.t()
  def to_ident(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/u, "-")
    |> String.replace(~r/[^\w-]/u, "")
    |> String.trim("-")
  end
end

defmodule Wyz.Markdown.Toc do
  @moduledoc """
  A structured table of contents by reading a parsed DOM AST and scanning for
  HTML heading tags.
  """

  require Logger
  defstruct rank: 0, node: nil, ident: nil, children: []

  @typedoc """
  A node in a table-of-contents tree.

  Each node contains a numeric rank, the HTML it displays, a DOM-wide unique
  identifier, and possibly a list of child nodes.

  Child nodes are nodes with greater rank than this which follow it until a node
  with equal or lesser rank occurs.
  """
  @type t :: %__MODULE__{
          rank: integer(),
          node: Earmark.ast_node() | nil,
          ident: String.t() | nil,
          children: [__MODULE__.t()]
        }

  @doc """
  Reads an Earmark AST and produces a table of contents from its headings.

  ## Parameters

  1. `ast`: a successfully parsed AST from `Earmark.Parser.as_ast`.
  2. `keep`: a subrange of `1..6` indicating which headings are kept in the
     table. Many documents exclude `<h1>` (the document title) or `<h4>` and
     above (not worth linking to), and so would provide `2..3`.
  """
  @spec read_ast(Earmark.ast(), Range.t(1, 6)) :: __MODULE__.t()
  def read_ast(ast, keep \\ 1..6) do
    ast
    |> filter_headings(keep)
    |> Stream.map(fn %__MODULE__{node: {_, attrs, _, _}} = this ->
      id =
        case List.keyfind(attrs, "id", 0) do
          {"id", id} -> id
          nil -> nil
        end

      %__MODULE__{this | ident: id}
    end)
    |> make_tree()
  end

  @doc """
  Converts a stream of Toc items into a table-of-contents tree.
  """
  @spec make_tree(Enumerable.t(__MODULE__.t())) :: [__MODULE__.t()]
  def make_tree(ast)
  def make_tree([]), do: []

  def make_tree([%__MODULE__{rank: rank} = head | tail]) do
    # Find the index of a node that is the same or lesser rank than this
    split = Enum.find_index(tail, fn %__MODULE__{rank: r} -> r <= rank end)

    # All nodes ahead of that index are children; all nodes after are siblings
    {children, siblings} =
      if split do
        Enum.split(tail, split)
      else
        {tail, []}
      end

    # Convert the two sub-lists into trees and attach them to this item.
    [
      %__MODULE__{head | children: make_tree(children)}
      | make_tree(siblings)
    ]
  end

  # The first invocation is probably with a Stream, not a list.
  def make_tree(ast), do: ast |> Enum.to_list() |> make_tree()

  @doc """
  Winnows a parsed AST down to a flat stream of heading elements.

  Yields a sequence of `{rank, node}` pairs, where `rank` is the integer rank of
  the heading element (1 for `<h1>`, etc.) and `node` is the Earmark parsed AST
  node.

  This is resistant to malformed HTML where a heading tag contains another
  nested heading tag inside it, as once a heading tag is detected in the stream,
  its child nodes are _not_ scanned.
  """
  @spec filter_headings(Earmark.ast(), Range.t(1, 6)) :: Enumerable.t(__MODULE__.t())
  def filter_headings(ast, keep)
  # A list of nodes filters each node
  def filter_headings(ast, keep) when is_list(ast),
    do: Stream.flat_map(ast, &filter_headings(&1, keep))

  # A text node produces nothing
  def filter_headings(text, _) when is_binary(text), do: []
  # A structured node either produces a heading, or produces a stream of its
  # filtered inner nodes
  def filter_headings({tag, _, inner, _} = node, keep) do
    case html_tag_to_rank(tag) do
      nil ->
        Stream.flat_map(inner, &filter_headings(&1, keep))

      rank ->
        if rank in keep,
          do: [%__MODULE__{rank: rank, node: node}],
          else: []
    end
  end

  @spec html_tag_to_rank(String.t()) :: 1..6 | nil
  def html_tag_to_rank(tag)

  def html_tag_to_rank("h1"), do: 1
  def html_tag_to_rank("h2"), do: 2
  def html_tag_to_rank("h3"), do: 3
  def html_tag_to_rank("h4"), do: 4
  def html_tag_to_rank("h5"), do: 5
  def html_tag_to_rank("h6"), do: 6
  def html_tag_to_rank(_), do: nil
end

defmodule Wyz.Markdown.Idents do
  @moduledoc """
  Dictionary of unique identifiers used within a DOM.

  DOMs require that each identifier be unique in the whole document, so whenever
  inserting an identifier more than once, a serial number is appended to it.

  NOTE: this does not currently defend against forcing duplicates, e.g. storing
  `"ident"`, `"ident"` again (producing `"ident-1"`), and then the string
  `"ident-1"`.
  """

  use Agent

  def start_link(_opts \\ []), do: Agent.start_link(&Map.new/0)

  @doc """
  Produces a unique identifier matching the input string.
  """
  @spec identify(pid() | nil, String.t()) :: String.t()
  def identify(nil, ident), do: ident

  def identify(this, ident) do
    Agent.get_and_update(this, fn idents ->
      case Map.get(idents, ident) do
        nil -> {ident, Map.put(idents, ident, 1)}
        num -> {"#{ident}-#{num}", %{idents | ident => num + 1}}
      end
    end)
  end

  @doc """
  Evicts the stored identifier memory, resetting the worker back to empty.
  """
  def reset(this), do: Agent.update(this, fn _ -> %{} end)

  def stop(this), do: Agent.stop(this)
end
