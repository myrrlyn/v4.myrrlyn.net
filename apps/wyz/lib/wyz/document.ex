defmodule Wyz.Document do
  @moduledoc """
  A displayable document, consisting of plaintext (in Markdown) and optionally
  structured metadata.

  This is currently intended only to be used with Markdown text.
  """

  require Logger
  require OK
  use OK.Pipe

  defstruct file: nil, text: nil, meta: %{}

  @type t :: %__MODULE__{
          file: Wyz.File.t() | :literal | nil,
          text: String.t() | {String.t(), String.t()} | nil,
          meta: %{String.t() => any()}
        }

  @doc """
  Creates a `Document` from a file on disk.
  """
  @spec load(Path.t()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def load(path) do
    OK.for do
      file <- Wyz.File.load(path)
    after
      text = file.data
      %__MODULE__{file: %Wyz.File{file | data: nil}, text: text}
    end
  end

  @doc """
  Creates a `Document` from an in-memory string. The `.file` member is set to
  `:literal`.
  """
  @spec from_string(String.t()) :: {:ok, __MODULE__.t()}
  def from_string(text), do: {:ok, %__MODULE__{file: :literal, text: text}}

  @doc """
  Splits the document contents into a frontmatter and a main content.

  After this function, the `.text` field will be a 2-tuple, where the first
  element is the text of the frontmatter block and the second is the remainder
  of the text.

  The frontmatter block is delimited by the first line of the source text being
  composed only of at least three hyphens, followed by arbitrary text, followed
  by another line that exactly matches the first line of the source text.

  This function is idempotent.
  """
  @spec split_frontmatter(__MODULE__.t()) :: {:ok, __MODULE__.t()} | {:error, String.t()}
  def split_frontmatter(this)
  def split_frontmatter(%__MODULE__{text: {_head, _body}} = this), do: {:ok, this}

  def split_frontmatter(%__MODULE__{text: text} = this) when is_binary(text) do
    text =
      text
      |> String.replace(~r/^\xef\xbb\xbf/, "")
      |> String.trim_leading()
      |> String.replace("\r", "")

    OK.for do
      {head, body} <-
        if String.starts_with?(text, "---") do
          [delim, rest] = text |> String.split("\n", parts: 2)

          case rest |> String.split(~r/^#{delim}$/m, parts: 2) do
            [_] -> {:error, "document text does not contain a metadata block terminator"}
            [head, body] -> {:ok, {String.trim(head), String.trim(body)}}
          end
        else
          {:error, "document text does not begin with a metadata block delimiter"}
        end
    after
      %__MODULE__{this | text: {head, body}}
    end
  end

  @doc """
  Parses the frontmatter of a document as YAML into a simple map.
  """
  @spec parse_frontmatter_yaml(__MODULE__.t()) :: {:ok, __MODULE__.t()} | {:error, any()}
  def parse_frontmatter_yaml(this)

  def parse_frontmatter_yaml(%__MODULE__{text: {head, _}} = this) when is_binary(head) do
    OK.for do
      yaml <- YamlElixir.read_from_string(head)
    after
      %__MODULE__{this | meta: yaml}
    end
  end

  def parse_frontmatter_yaml(%__MODULE__{text: text} = this) when is_binary(text),
    do: this |> __MODULE__.split_frontmatter() ~>> __MODULE__.parse_frontmatter_yaml()

  def parse_frontmatter_yaml(_), do: {:error, :invalid_contents}

  @spec date_from_filename(__MODULE__.t()) :: NaiveDateTime.t() | nil
  def date_from_filename(this)
  def date_from_filename(%__MODULE__{file: %Wyz.File{} = file}), do: Wyz.File.date_from_name(file)
  def date_from_filename(%__MODULE__{}), do: nil
end
