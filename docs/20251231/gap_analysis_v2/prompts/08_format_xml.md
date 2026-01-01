# Implementation Prompt: Format.XML

## Task

Implement XML file parsing for loading datasets from XML documents.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/format.ex` - Format registry and behaviour
2. `lib/dataset_manager/format/json.ex` - Similar format parser example
3. `lib/dataset_manager/format/csv.ex` - Another format parser example
4. `test/dataset_manager/format/json_test.exs` - Test patterns

## Context

XML is still commonly used for:
- Legacy data systems
- SOAP/REST API responses
- Configuration files with data
- Scientific data formats

The Python `datasets` library supports loading from XML with configurable element selection.

## Requirements

### 1. Format.XML module

```elixir
defmodule HfDatasetsEx.Format.XML do
  @moduledoc """
  Parse XML files into dataset items.

  Supports both DOM parsing for small files and SAX streaming for large files.
  """

  @behaviour HfDatasetsEx.Format

  @doc """
  Parse an XML file into a list of maps.

  ## Options

    * `:row_tag` - Element tag name that represents a row (default: "row")
    * `:encoding` - Character encoding (default: :utf8)
    * `:stream` - Use SAX streaming for large files (default: false)

  ## Examples

      # Simple XML
      # <data>
      #   <item><name>Alice</name><age>30</age></item>
      #   <item><name>Bob</name><age>25</age></item>
      # </data>

      {:ok, items} = Format.XML.parse("data.xml", row_tag: "item")
      # [%{"name" => "Alice", "age" => "30"}, %{"name" => "Bob", "age" => "25"}]

  """
  @spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
end
```

## File to Create

`lib/dataset_manager/format/xml.ex`

## Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    # Existing deps...
    {:sweet_xml, "~> 0.7", optional: true}
  ]
end
```

## Implementation

```elixir
defmodule HfDatasetsEx.Format.XML do
  @moduledoc """
  Parse XML files into dataset items.
  """

  @behaviour HfDatasetsEx.Format

  @impl true
  def extensions, do: [".xml"]

  @impl true
  def parse(path, opts \\ []) do
    row_tag = Keyword.get(opts, :row_tag, "row")
    stream = Keyword.get(opts, :stream, false)

    if stream do
      parse_streaming(path, row_tag, opts)
    else
      parse_dom(path, row_tag, opts)
    end
  rescue
    e in [File.Error] ->
      {:error, {:file_error, e.reason}}
    e ->
      {:error, {:parse_error, Exception.message(e)}}
  end

  # DOM-based parsing for smaller files
  defp parse_dom(path, row_tag, _opts) do
    require_sweet_xml!()

    import SweetXml

    content = File.read!(path)

    items =
      content
      |> xpath(~x"//#{row_tag}"l)
      |> Enum.map(&element_to_map/1)

    {:ok, items}
  end

  # SAX-based streaming for large files
  defp parse_streaming(path, row_tag, _opts) do
    require_sweet_xml!()

    import SweetXml

    items =
      path
      |> File.stream!()
      |> stream_tags(row_tag)
      |> Stream.map(&element_to_map/1)
      |> Enum.to_list()

    {:ok, items}
  end

  # Convert an XML element to a map
  defp element_to_map(element) do
    import SweetXml

    # Get all child elements
    children = xpath(element, ~x"./*"l)

    if Enum.empty?(children) do
      # Leaf node - return text content
      xpath(element, ~x"./text()"s)
    else
      # Branch node - recursively convert children
      children
      |> Enum.map(fn child ->
        name = xpath(child, ~x"name(.)"s)
        value = element_to_map(child)
        {name, value}
      end)
      |> Map.new()
    end
  end

  # Handle nested attributes
  defp extract_attributes(element) do
    import SweetXml

    element
    |> xpath(~x"./@*"l)
    |> Enum.map(fn attr ->
      name = xpath(attr, ~x"name(.)"s)
      value = xpath(attr, ~x"."s)
      {"@" <> name, value}
    end)
    |> Map.new()
  end

  defp require_sweet_xml! do
    unless Code.ensure_loaded?(SweetXml) do
      raise """
      SweetXml is required for XML parsing.
      Add {:sweet_xml, "~> 0.7"} to your mix.exs dependencies.
      """
    end
  end
end
```

## Register Format

Update `lib/dataset_manager/format.ex`:

```elixir
defmodule HfDatasetsEx.Format do
  @formats %{
    # Existing formats...
    ".xml" => HfDatasetsEx.Format.XML
  }
end
```

## Tests

Create `test/dataset_manager/format/xml_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.XMLTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.XML

  @fixtures_path "test/fixtures/xml"

  setup do
    File.mkdir_p!(@fixtures_path)

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "parse/2" do
    test "parses simple XML with default row tag" do
      xml = """
      <?xml version="1.0"?>
      <data>
        <row>
          <name>Alice</name>
          <age>30</age>
        </row>
        <row>
          <name>Bob</name>
          <age>25</age>
        </row>
      </data>
      """

      path = Path.join(@fixtures_path, "simple.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path)

      assert length(items) == 2
      assert %{"name" => "Alice", "age" => "30"} = Enum.at(items, 0)
      assert %{"name" => "Bob", "age" => "25"} = Enum.at(items, 1)
    end

    test "parses with custom row_tag" do
      xml = """
      <?xml version="1.0"?>
      <catalog>
        <product>
          <name>Widget</name>
          <price>9.99</price>
        </product>
        <product>
          <name>Gadget</name>
          <price>19.99</price>
        </product>
      </catalog>
      """

      path = Path.join(@fixtures_path, "products.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path, row_tag: "product")

      assert length(items) == 2
      assert %{"name" => "Widget", "price" => "9.99"} = Enum.at(items, 0)
    end

    test "handles nested elements" do
      xml = """
      <?xml version="1.0"?>
      <data>
        <item>
          <name>Test</name>
          <metadata>
            <source>API</source>
            <version>1.0</version>
          </metadata>
        </item>
      </data>
      """

      path = Path.join(@fixtures_path, "nested.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path, row_tag: "item")

      assert length(items) == 1
      item = hd(items)
      assert item["name"] == "Test"
      assert item["metadata"]["source"] == "API"
      assert item["metadata"]["version"] == "1.0"
    end

    test "handles empty elements" do
      xml = """
      <?xml version="1.0"?>
      <data>
        <row>
          <name>Test</name>
          <description></description>
        </row>
      </data>
      """

      path = Path.join(@fixtures_path, "empty.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path)

      assert length(items) == 1
      assert %{"name" => "Test", "description" => ""} = hd(items)
    end

    test "returns error for missing file" do
      {:error, {:file_error, :enoent}} = XML.parse("nonexistent.xml")
    end

    test "returns error for invalid XML" do
      path = Path.join(@fixtures_path, "invalid.xml")
      File.write!(path, "<not>valid<xml>")

      {:error, {:parse_error, _}} = XML.parse(path)
    end

    test "handles no matching rows" do
      xml = """
      <?xml version="1.0"?>
      <data>
        <other>stuff</other>
      </data>
      """

      path = Path.join(@fixtures_path, "no_rows.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path)

      assert items == []
    end
  end

  describe "parse/2 with streaming" do
    @tag :slow
    test "streams large XML files" do
      # Generate large XML
      rows = Enum.map(1..1000, fn i ->
        "<row><id>#{i}</id><value>test#{i}</value></row>"
      end)

      xml = """
      <?xml version="1.0"?>
      <data>
      #{Enum.join(rows, "\n")}
      </data>
      """

      path = Path.join(@fixtures_path, "large.xml")
      File.write!(path, xml)

      {:ok, items} = XML.parse(path, stream: true)

      assert length(items) == 1000
      assert %{"id" => "1", "value" => "test1"} = hd(items)
    end
  end

  describe "extensions/0" do
    test "returns xml extension" do
      assert XML.extensions() == [".xml"]
    end
  end
end
```

## Test Fixtures

Create `test/fixtures/xml/.gitkeep` (directory will be created at runtime)

## Edge Cases

1. **CDATA sections**: Should be handled as text content
2. **Namespaces**: Should work with namespaced elements
3. **Attributes**: Consider including as `@attr` keys
4. **Mixed content**: Elements with both text and child elements
5. **Large files**: Use streaming mode to avoid memory issues
6. **Encoding**: Handle different encodings (UTF-8, ISO-8859-1)

## Future Enhancements

1. **XPath selection**: Allow complex XPath expressions for row selection
2. **Attribute extraction**: Option to include XML attributes
3. **Namespace handling**: Support for namespace prefixes
4. **Schema validation**: Optional XSD validation
5. **XSLT transformation**: Apply XSLT before parsing

## Acceptance Criteria

1. `mix test test/dataset_manager/format/xml_test.exs` passes
2. `mix credo --strict` has no new issues
3. `mix dialyzer` has no new warnings
4. Format auto-detected from `.xml` extension
5. Graceful error handling for malformed XML
6. Documentation includes examples

## Python Parity Notes

Python `datasets` XML loader features:
- `field` parameter for nested extraction (we use `row_tag`)
- Automatic type inference (we return strings, cast separately)
- Streaming via `iterparse` (we support via `stream: true`)
