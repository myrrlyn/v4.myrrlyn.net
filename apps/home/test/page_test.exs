defmodule PageTest do
  use ExUnit.Case
  alias Home.Page

  doctest Home.Page
  doctest Home.Page.Metadata

  test "processes metadata" do
    now = Timex.now()

    text = """
    title: Test Document
    date: #{Timex.format!(now, "{RFC3339z}")}
    toc: false
    tags:
      - testing
      - examples
    """

    {:ok, meta} = Page.Metadata.from_string(text)
    assert meta.title == "Test Document"
    assert meta.date == now
    assert !meta.show_toc
    assert length(meta.tags) == 2
  end

  test "load from disk" do
    {:ok, page} = Home.Page.load_page("index.md")
    IO.inspect(page)
  end
end
