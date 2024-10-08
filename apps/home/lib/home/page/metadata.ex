defmodule Home.Page.Metadata do
  @moduledoc """
  Additional information about documents used as individual pages.

  This is kept here, rather than in `Wyz.Document`, as it is typed specifically
  for the website, while `Wyz.Document` is intended to be generic over any
  Markdown document, regardless of application.
  """

  require Floki
  require Logger
  require OK
  use OK.Pipe

  defstruct title: nil,
            subtitle: nil,
            page_title: nil,
            date: nil,
            about: nil,
            summary: nil,
            show_toc: true,
            published: true,
            tags: [],
            metadata: [],
            extra: %{}

  @typedoc """
  This application specifies a number of keys in its business logic. All others
  are held in the `extra` block.
  """
  @type t :: %__MODULE__{
          # Presentational title in an `<h1>`.
          title: String.t() | nil,
          # Presentational subtitle in an `<h2>`.
          subtitle: String.t() | nil,
          # Browser title in `<title>` and the sitemap. Defaults to `.tite`.
          page_title: String.t() | nil,
          # Date of publication.
          date: DateTime.t() | NaiveDateTime.t() | nil,
          # Information about the article, displayed in the sidebar.
          about: String.t() | nil,
          # Information about the article, kept in `<head>`. Defaults to `.about`.
          summary: String.t() | nil,
          # Whether to print the ToC in the sidebar.
          show_toc: bool | Range.t(),
          # Whether to show the article in the sitemap (or even serve it at all).
          published: bool,
          # Probably never going to use this.
          tags: [String.t()],
          # Additional key/value data used to describe the page in.
          metadata: [{String.t(), String.t()}],
          # Anything else.
          extra: %{String.t() => any}
        }

  @behaviour Access

  @doc """
  Parses a `Metadata` structure directly from its representative text.
  """
  @spec from_string(String.t()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def from_string(text) when is_binary(text) do
    text |> YamlElixir.read_from_string() ~>> __MODULE__.from_yaml()
  end

  @doc """
  Converts a YAML structure into a `Metadata` object. Known keys will be
  processed into their respective fields, and unknown keys will be preserved in
  `.extra`.
  """
  @spec from_yaml(map()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def from_yaml(yaml) do
    yaml
    |> Enum.map(&__MODULE__.transform/1)
    |> Enum.reduce({:ok, %__MODULE__{}}, fn {path, value}, this ->
      OK.for do
        this <- this
        value <- value
      after
        put_in(this, path, value)
      end
    end)
  end

  @spec from_html(String.t() | Floki.html_tree()) :: {:ok, __MODULE__.t()} | {:error, term()}
  def from_html(html)
  def from_html(html) when is_binary(html), do: html |> Floki.parse_document() ~> from_html()

  def from_html(html) do
    meta = html |> Floki.find("meta[name^=\"wyz-\"]")

    page_title = html |> Floki.find("title") |> get_node_text()
    title = html |> Floki.find("h1") |> get_node_text()
    subtitle = html |> Floki.find("h1 + h2") |> get_node_text()

    published = get_floki_value(meta, "published") |> List.first("1") != "0"

    {:ok,
     %__MODULE__{title: title, subtitle: subtitle, page_title: page_title, published: published}}
  end

  def get_node_text(html) when is_list(html) do
    html
    |> Enum.take(1)
    |> Enum.map(fn {_, _, inner} -> inner end)
    |> Enum.map(&Floki.text/1)
    |> List.first()
  end

  def update_document(%Wyz.Document{} = doc) do
    OK.for do
      %Wyz.Document{meta: yaml} = doc2 <- Wyz.Document.parse_frontmatter_yaml(doc)
      meta <- __MODULE__.from_yaml(yaml)
    after
      %Wyz.Document{
        doc2
        | meta: %__MODULE__{
            meta
            | date:
                case meta.date do
                  nil -> Wyz.Document.date_from_filename(doc)
                  %DateTime{} = dt -> dt
                  %NaiveDateTime{} = ndt -> ndt
                end
          }
      }
    end
  end

  def get_floki_value(html, name) do
    html |> Floki.attribute("[name$=\"-#{name}\"]", "value")
  end

  @doc """
  Translates each key/value pair of a mapping into the suitable field-name
  and/or data type.

  Overloads should be provided for each key/value that requires custom logic.
  """
  @spec transform({String.t(), any()}) :: {[Access.t()], {:ok, any()} | {:error, any()}}
  def transform(key_val)

  # `toc:` in text, but `.show_toc` in code.
  def transform({"toc", [lo, hi]}) when is_integer(lo) and is_integer(hi),
    do: {[Access.key(:show_toc)], {:ok, lo..hi}}

  def transform({"toc", show_toc}), do: {[Access.key(:show_toc)], {:ok, show_toc}}

  def transform({"date", text}) when is_binary(text) do
    with {:error, _} <- Timex.parse(text, "{RFC3339z}"),
         {:error, _} <- Timex.parse(text, "{RFC3339}"),
         {:error, _} <- Timex.parse(text, "{ISO:Extended}"),
         {:isodate, {:error, _}} <- {:isodate, Timex.parse(text, "{ISOdate}")} do
      {:error,
       "YAML frontmatter date values must be well-formed RFC-3339 or ISO-8601 date or date-time strings"}
    else
      {:ok, date} -> {:ok, date}
      {:isodate, {:ok, date}} -> DateTime.from_naive(date, "Etc/UTC")
    end
    |> (fn out -> {[Access.key(:date)], out} end).()
  end

  # Known keys translate directly to their field; unknowns are placed in
  # `.extra`.
  def transform({key, value}) when is_binary(key) do
    known = __MODULE__.known_keys() |> Enum.map(&to_string/1)

    path =
      if key in known,
        do: [key |> String.to_atom() |> Access.key()],
        else: [Access.key(:extra), key]

    {path, {:ok, value}}
  end

  @doc """
  Lists all statically-known keys in the metadata.
  """
  @spec known_keys() :: [atom()]
  def known_keys(),
    do: %__MODULE__{} |> Map.keys() |> Enum.reject(&(&1 in [:__struct__, :extra]))

  @doc """
  Constructs an `[Access.t()]` list from the provided key that can be used to
  dynamically access the metadata.
  """
  @spec path_for_key(atom() | String.t()) :: [Access.key()]
  def path_for_key(key)

  def path_for_key(key) when is_atom(key) do
    if key in __MODULE__.known_keys(),
      do: [Access.key(key)],
      else: [Access.key(:extra), Access.key(to_string(key))]
  end

  def path_for_key(key) when is_binary(key) do
    if key in (__MODULE__.known_keys() |> Enum.map(&to_string/1)),
      do: [key |> String.to_atom() |> Access.key()],
      else: [Access.key(:extra), Access.key(key)]
  end

  # From `Access`

  def fetch(%__MODULE__{} = this, key) do
    case get_in(this, __MODULE__.path_for_key(key)) do
      nil -> :error
      val -> {:ok, val}
    end
  end

  def get_and_update(%__MODULE__{} = this, key, func) do
    value = __MODULE__.fetch(this, key)

    case func.(value) do
      :pop ->
        {this, put_in(this, __MODULE__.path_for_key(key), nil)}

      {get, update} ->
        put_in(this, __MODULE__.path_for_key(key), update)
        {get, this}

      other ->
        raise "the given function must return a two-element tuple or :pop, got: #{inspect(other)}"
    end
  end

  def pop(%__MODULE__{} = this, key) do
    path = __MODULE__.path_for_key(key)
    {get_in(this, path), put_in(this, path, nil)}
  end
end
