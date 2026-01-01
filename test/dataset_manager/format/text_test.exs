defmodule HfDatasetsEx.Format.TextTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.Text

  @fixtures_dir Path.join(System.tmp_dir!(), "text_format_test_#{:rand.uniform(100_000)}")

  setup_all do
    File.mkdir_p!(@fixtures_dir)

    # Basic text file
    File.write!(Path.join(@fixtures_dir, "basic.txt"), """
    Hello world
    How are you
    Goodbye
    """)

    # File with empty lines
    File.write!(Path.join(@fixtures_dir, "empty_lines.txt"), """
    Line 1

    Line 2

    Line 3
    """)

    # Unicode file
    File.write!(Path.join(@fixtures_dir, "unicode.txt"), """
    Hello 世界
    Привет мир
    مرحبا بالعالم
    """)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    :ok
  end

  describe "parse/2" do
    test "parses basic text file" do
      path = Path.join(@fixtures_dir, "basic.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
      assert hd(items) == %{"text" => "Hello world"}
    end

    test "skips empty lines by default" do
      path = Path.join(@fixtures_dir, "empty_lines.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
    end

    test "keeps empty lines when skip_empty: false" do
      path = Path.join(@fixtures_dir, "empty_lines.txt")

      assert {:ok, items} = Text.parse(path, skip_empty: false)
      assert length(items) == 5
    end

    test "uses custom column name" do
      path = Path.join(@fixtures_dir, "basic.txt")

      assert {:ok, items} = Text.parse(path, column: "content")
      assert hd(items) == %{"content" => "Hello world"}
    end

    test "handles unicode" do
      path = Path.join(@fixtures_dir, "unicode.txt")

      assert {:ok, items} = Text.parse(path)
      assert length(items) == 3
      assert hd(items)["text"] =~ "世界"
    end
  end

  describe "parse_stream/2" do
    test "returns stream" do
      path = Path.join(@fixtures_dir, "basic.txt")

      stream = Text.parse_stream(path)
      items = Enum.to_list(stream)

      assert length(items) == 3
    end

    test "stream is lazy" do
      path = Path.join(@fixtures_dir, "basic.txt")

      stream = Text.parse_stream(path)

      # Take only 1
      assert [first] = Enum.take(stream, 1)
      assert first["text"] == "Hello world"
    end
  end
end
