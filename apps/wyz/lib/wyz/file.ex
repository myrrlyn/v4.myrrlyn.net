defmodule Wyz.File do
  @moduledoc """
  Represents a stored file, retaining its path and filesystem information.

  This is intended to be used as a carrier for _any_ type of file.
  """

  require OK

  defstruct path: nil, stat: nil, data: nil

  @type t :: %__MODULE__{path: Path.t() | nil, stat: File.Stat.t() | nil, data: binary() | nil}

  def from_path(path), do: %__MODULE__{path: path}

  @doc """
  Reads the contents of a file into memory.
  """
  @spec load(Path.t() | __MODULE__.t()) :: {:ok, __MODULE__.t()} | {:error, File.posix()}
  def load(this)
  def load(%__MODULE__{path: path}), do: load(path)

  def load(path) when is_binary(path) do
    OK.for do
      stat <- File.stat(path, time: :posix)
      data <- File.read(path)
    after
      %__MODULE__{path: path, stat: stat, data: data}
    end
  end

  @spec date_from_name(__MODULE__.t()) :: NaiveDateTime.t() | nil
  def date_from_name(%__MODULE__{path: path}) do
    case Regex.run(~r/^[0-9-]{10}/, Path.basename(path)) do
      [date] ->
        case Timex.parse(date, "{ISOdate}") do
          {:ok, ndt} -> ndt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec mtime(__MODULE__.t()) :: {:ok, DateTime.t()} | {:error, atom()}
  def mtime(this)

  def mtime(%__MODULE__{stat: %File.Stat{mtime: mtime}}) do
    DateTime.from_unix(mtime)
  end
end
