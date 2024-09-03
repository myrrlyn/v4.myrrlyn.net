defmodule WyzTest do
  use ExUnit.Case

  doctest Wyz

  test "handles document literals" do
    text = """
    ---
    key: value
    hello: world
    ---

    main file contents
    """

    {:ok, doc} = Wyz.Document.from_string(text)
    assert doc.file == :literal
    assert doc.text == text

    {:ok, doc} = Wyz.Document.split_frontmatter(doc)
    assert doc.text == {"key: value\nhello: world", "main file contents"}

    {:ok, doc} = Wyz.Document.split_frontmatter(doc)
    assert doc.text == {"key: value\nhello: world", "main file contents"}

    {:ok, doc} = Wyz.Document.parse_frontmatter_yaml(doc)
    assert doc.meta == %{"key" => "value", "hello" => "world"}
  end
end
