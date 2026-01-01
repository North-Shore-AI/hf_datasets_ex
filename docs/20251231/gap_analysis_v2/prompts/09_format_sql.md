# Implementation Prompt: Format.SQL

## Task

Implement SQL database loading for creating datasets from SQL queries or tables.

## Pre-Implementation Reading

Read these files to understand the existing codebase:

1. `lib/dataset_manager/format.ex` - Format registry and behaviour
2. `lib/dataset_manager/dataset.ex` - Dataset.from_* patterns
3. `mix.exs` - Current dependencies (note: Ecto is optional)

## Context

SQL databases are a primary data source for many ML workflows. The Python `datasets` library supports:
- Loading from SQL queries
- Loading from table names
- Streaming large result sets

In Elixir, we integrate with Ecto for database access.

## Requirements

### 1. Format.SQL module

```elixir
defmodule HfDatasetsEx.Format.SQL do
  @moduledoc """
  Load data from SQL databases via Ecto.

  Requires an Ecto Repo configured in your application.
  """

  @doc """
  Load data from a SQL query.

  ## Options

    * `:params` - Query parameters (default: [])
    * `:batch_size` - For streaming large results (default: 1000)
    * `:stream` - Return stream instead of list (default: false)

  ## Examples

      {:ok, items} = Format.SQL.from_query(
        MyApp.Repo,
        "SELECT id, text, label FROM examples WHERE split = $1",
        params: ["train"]
      )

  """
  @spec from_query(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Load all rows from a table.

  ## Options

    * `:columns` - Specific columns to select (default: all)
    * `:where` - WHERE clause conditions
    * `:limit` - Maximum rows to return
    * `:batch_size` - For streaming (default: 1000)

  ## Examples

      {:ok, items} = Format.SQL.from_table(MyApp.Repo, "examples",
        columns: ["text", "label"],
        where: "split = 'train'",
        limit: 10000
      )

  """
  @spec from_table(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
end
```

## Files to Create

- `lib/dataset_manager/format/sql.ex`
- `test/dataset_manager/format/sql_test.exs`

## Dependencies

Add to `mix.exs` (optional dependency):

```elixir
defp deps do
  [
    # Existing deps...
    {:ecto_sql, "~> 3.10", optional: true}
  ]
end
```

## Implementation

```elixir
defmodule HfDatasetsEx.Format.SQL do
  @moduledoc """
  Load data from SQL databases via Ecto.

  This module provides integration with Ecto for loading datasets from
  SQL databases. It requires an Ecto Repo to be configured.

  ## Security

  This module includes protections against SQL injection:
  - Table/column names are validated against a whitelist pattern
  - Query parameters use Ecto's parameterized queries
  - WHERE clauses should use parameterized queries

  ## Examples

      # From a query
      {:ok, items} = SQL.from_query(MyRepo, "SELECT * FROM train_data")

      # From a table
      {:ok, items} = SQL.from_table(MyRepo, "examples", limit: 1000)

      # Streaming large results
      stream = SQL.stream_query(MyRepo, "SELECT * FROM large_table")
      Enum.each(stream, &process/1)

  """

  @valid_identifier ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  @doc """
  Execute a SQL query and return results as a list of maps.
  """
  @spec from_query(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def from_query(repo, sql, opts \\ []) do
    require_ecto_sql!()

    params = Keyword.get(opts, :params, [])

    case Ecto.Adapters.SQL.query(repo, sql, params) do
      {:ok, %{columns: columns, rows: rows}} ->
        items = rows_to_maps(columns, rows)
        {:ok, items}

      {:error, reason} ->
        {:error, {:query_error, reason}}
    end
  end

  @doc """
  Load all rows from a table.
  """
  @spec from_table(module(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def from_table(repo, table_name, opts \\ []) do
    require_ecto_sql!()

    with :ok <- validate_identifier(table_name) do
      columns = Keyword.get(opts, :columns, ["*"])
      where = Keyword.get(opts, :where)
      limit = Keyword.get(opts, :limit)

      # Validate column names if specified
      if columns != ["*"] do
        Enum.each(columns, fn col ->
          case validate_identifier(col) do
            :ok -> :ok
            {:error, reason} -> throw(reason)
          end
        end)
      end

      sql = build_select_query(table_name, columns, where, limit)
      from_query(repo, sql, opts)
    end
  catch
    reason -> {:error, {:invalid_identifier, reason}}
  end

  @doc """
  Stream query results for large datasets.

  Returns an Elixir Stream that can be lazily consumed.
  """
  @spec stream_query(module(), String.t(), keyword()) :: Enumerable.t()
  def stream_query(repo, sql, opts \\ []) do
    require_ecto_sql!()

    params = Keyword.get(opts, :params, [])
    batch_size = Keyword.get(opts, :batch_size, 1000)

    Stream.resource(
      fn -> init_stream(repo, sql, params, batch_size) end,
      &next_batch/1,
      &close_stream/1
    )
  end

  @doc """
  Stream all rows from a table.
  """
  @spec stream_table(module(), String.t(), keyword()) :: Enumerable.t()
  def stream_table(repo, table_name, opts \\ []) do
    with :ok <- validate_identifier(table_name) do
      columns = Keyword.get(opts, :columns, ["*"])
      where = Keyword.get(opts, :where)

      sql = build_select_query(table_name, columns, where, nil)
      stream_query(repo, sql, opts)
    else
      {:error, reason} -> raise ArgumentError, "Invalid table name: #{reason}"
    end
  end

  # Private helpers

  defp rows_to_maps(columns, rows) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp validate_identifier(name) do
    if Regex.match?(@valid_identifier, name) do
      :ok
    else
      {:error, "Invalid identifier: #{name}"}
    end
  end

  defp build_select_query(table, columns, where, limit) do
    cols = Enum.join(columns, ", ")
    base = "SELECT #{cols} FROM #{table}"

    base
    |> maybe_add_where(where)
    |> maybe_add_limit(limit)
  end

  defp maybe_add_where(sql, nil), do: sql
  defp maybe_add_where(sql, where), do: "#{sql} WHERE #{where}"

  defp maybe_add_limit(sql, nil), do: sql
  defp maybe_add_limit(sql, limit) when is_integer(limit), do: "#{sql} LIMIT #{limit}"

  # Streaming helpers

  defp init_stream(repo, sql, params, batch_size) do
    # Use cursor-based pagination
    %{
      repo: repo,
      sql: sql,
      params: params,
      batch_size: batch_size,
      offset: 0,
      done: false
    }
  end

  defp next_batch(%{done: true} = state) do
    {:halt, state}
  end

  defp next_batch(state) do
    %{repo: repo, sql: sql, params: params, batch_size: batch_size, offset: offset} = state

    paginated_sql = "#{sql} LIMIT #{batch_size} OFFSET #{offset}"

    case Ecto.Adapters.SQL.query(repo, paginated_sql, params) do
      {:ok, %{columns: columns, rows: rows}} when length(rows) > 0 ->
        items = rows_to_maps(columns, rows)
        new_state = %{state | offset: offset + batch_size}
        {items, new_state}

      {:ok, %{rows: []}} ->
        {:halt, %{state | done: true}}

      {:error, reason} ->
        raise "SQL streaming error: #{inspect(reason)}"
    end
  end

  defp close_stream(_state) do
    :ok
  end

  defp require_ecto_sql! do
    unless Code.ensure_loaded?(Ecto.Adapters.SQL) do
      raise """
      Ecto.Adapters.SQL is required for SQL format support.
      Add {:ecto_sql, "~> 3.10"} to your mix.exs dependencies.
      """
    end
  end
end
```

## Dataset Integration

Add convenience function to `HfDatasetsEx`:

```elixir
defmodule HfDatasetsEx do
  @doc """
  Load a dataset from a SQL query.

  ## Examples

      {:ok, dataset} = HfDatasetsEx.from_sql(
        MyApp.Repo,
        "SELECT text, label FROM examples WHERE split = 'train'"
      )

  """
  @spec from_sql(module(), String.t(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def from_sql(repo, sql, opts \\ []) do
    case Format.SQL.from_query(repo, sql, opts) do
      {:ok, items} -> {:ok, Dataset.from_list(items)}
      error -> error
    end
  end
end
```

## Tests

Create `test/dataset_manager/format/sql_test.exs`:

```elixir
defmodule HfDatasetsEx.Format.SQLTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Format.SQL

  # Mock repo for testing without a real database
  defmodule MockRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    # Simulated query results
    def query(sql, params \\ [])

    def query("SELECT * FROM users", []) do
      {:ok, %{
        columns: ["id", "name", "email"],
        rows: [
          [1, "Alice", "alice@example.com"],
          [2, "Bob", "bob@example.com"]
        ]
      }}
    end

    def query("SELECT name, email FROM users", []) do
      {:ok, %{
        columns: ["name", "email"],
        rows: [
          ["Alice", "alice@example.com"],
          ["Bob", "bob@example.com"]
        ]
      }}
    end

    def query("SELECT * FROM users WHERE active = $1", [true]) do
      {:ok, %{
        columns: ["id", "name", "email"],
        rows: [[1, "Alice", "alice@example.com"]]
      }}
    end

    def query("SELECT * FROM users LIMIT 1", []) do
      {:ok, %{
        columns: ["id", "name", "email"],
        rows: [[1, "Alice", "alice@example.com"]]
      }}
    end

    def query("INVALID SQL", []) do
      {:error, %{message: "syntax error"}}
    end
  end

  describe "from_query/3" do
    test "executes query and returns maps" do
      # This test requires mocking Ecto.Adapters.SQL.query
      # In real tests, use a test database or mocking library
    end

    test "handles query parameters" do
      # Test with parameterized queries
    end

    test "returns error for invalid SQL" do
      # Test error handling
    end
  end

  describe "from_table/3" do
    test "loads all rows from table" do
      # Test table loading
    end

    test "respects columns option" do
      # Test column selection
    end

    test "respects limit option" do
      # Test limit
    end

    test "rejects invalid table names" do
      {:error, {:invalid_identifier, _}} = SQL.from_table(MockRepo, "users; DROP TABLE users")
    end

    test "rejects invalid column names" do
      {:error, _} = SQL.from_table(MockRepo, "users", columns: ["valid", "name; --"])
    end
  end

  describe "validate_identifier/1" do
    test "accepts valid identifiers" do
      assert :ok = SQL.validate_identifier("users")
      assert :ok = SQL.validate_identifier("user_data")
      assert :ok = SQL.validate_identifier("Users123")
      assert :ok = SQL.validate_identifier("_private")
    end

    test "rejects invalid identifiers" do
      assert {:error, _} = SQL.validate_identifier("1invalid")
      assert {:error, _} = SQL.validate_identifier("table name")
      assert {:error, _} = SQL.validate_identifier("users;")
      assert {:error, _} = SQL.validate_identifier("users--")
      assert {:error, _} = SQL.validate_identifier("")
    end
  end

  describe "stream_query/3" do
    @tag :slow
    test "streams results in batches" do
      # Test streaming behavior
    end
  end
end
```

## Integration Test

For real database testing (tagged to skip in CI without database):

```elixir
defmodule HfDatasetsEx.Format.SQLIntegrationTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag :database

  # Only run if DATABASE_URL is set
  setup do
    unless System.get_env("DATABASE_URL") do
      :skip
    end
  end

  test "loads from real database" do
    # Integration test with actual database
  end
end
```

## Security Considerations

1. **SQL Injection**: Use parameterized queries, validate identifiers
2. **Data Exposure**: Only allow read operations (SELECT)
3. **Resource Limits**: Implement query timeouts and row limits
4. **Connection Pooling**: Use Ecto's built-in pooling

## Edge Cases

1. **NULL values**: Convert to nil
2. **Binary data**: Handle BLOB columns
3. **Large integers**: Handle BIGINT properly
4. **Timestamps**: Convert to DateTime
5. **JSON columns**: Parse as maps
6. **Empty results**: Return empty list, not error

## Future Enhancements

1. **Write support**: `Dataset.to_sql/3` for inserting data
2. **Type inference**: Infer Features from SQL schema
3. **Transactions**: Support transactional reads
4. **Connection options**: Custom connection configurations
5. **Query building**: Ecto-style query builder

## Acceptance Criteria

1. All tests pass
2. SQL injection protection verified
3. Streaming works for large datasets
4. Error messages are helpful
5. Documentation includes security notes
6. Works with PostgreSQL, MySQL, SQLite

## Python Parity Notes

Python `datasets` SQL features:
- `from_sql(sql, con)` - We use `from_query(repo, sql)`
- pandas-style connection strings - We use Ecto repos
- Chunked reading - We provide `stream_query/3`
