# Implementation Checklist for 100% Feature Parity

**Goal**: Achieve 100% feature parity with Python HuggingFace `datasets` library
**Status**: ~66% complete (96/145 features)
**Target**: 145/145 features

---

## Quick Reference: Priority Order

| Order | Feature | Complexity | Prompt File | Est. Test Count |
|-------|---------|------------|-------------|-----------------|
| 1 | DatasetDict.map/filter | Low | `01_dataset_dict_ops.md` | 6 |
| 2 | IterableDataset.concatenate | Low | `02_iterable_concatenate.md` | 4 |
| 3 | Dataset.repeat | Low | `03_dataset_repeat.md` | 5 |
| 4 | Format.ImageFolder | Low | `04_imagefolder_format.md` | 8 |
| 5 | Export.Disk save/load | Medium | `05_save_load_disk.md` | 10 |
| 6 | IterableDataset.interleave | Medium | `06_iterable_interleave.md` | 8 |
| 7 | Dataset.with_transform | Medium | `07_with_transform.md` | 12 |
| 8 | Format.XML | Medium | `08_format_xml.md` | 8 |
| 9 | Format.SQL | Medium | `09_format_sql.md` | 10 |
| 10 | Format.AudioFolder | Low | `10_audiofolder_format.md` | 6 |
| 11 | Format.WebDataset | Medium | `11_webdataset_format.md` | 8 |

---

## Phase 1: Quick Wins (Low Complexity)

### 1.1 DatasetDict.map/3 and filter/3

- [ ] Read `01_dataset_dict_ops.md`
- [ ] Write test file: `test/dataset_manager/dataset_dict_ops_test.exs`
- [ ] Implement `DatasetDict.map/3`
- [ ] Implement `DatasetDict.filter/3`
- [ ] Run `mix test test/dataset_manager/dataset_dict_ops_test.exs`
- [ ] Run `mix format`
- [ ] Run `mix credo --strict`
- [ ] Run `mix dialyzer`

**TDD Test Example**:
```elixir
test "map applies function to all splits" do
  dd = sample_dataset_dict()
  result = DatasetDict.map(dd, &Map.put(&1, "x", 1))

  for {_, ds} <- result.datasets do
    assert Enum.all?(ds.items, &(&1["x"] == 1))
  end
end
```

---

### 1.2 IterableDataset.concatenate/1

- [ ] Read `02_iterable_concatenate.md`
- [ ] Write test file: `test/dataset_manager/iterable_dataset_concatenate_test.exs`
- [ ] Implement `IterableDataset.concatenate/1`
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "concatenates two streams" do
  s1 = IterableDataset.from_stream([1, 2])
  s2 = IterableDataset.from_stream([3, 4])

  result = IterableDataset.concatenate([s1, s2])
  items = Enum.to_list(result)

  assert items == [1, 2, 3, 4]
end
```

---

### 1.3 Dataset.repeat/2

- [ ] Read `03_dataset_repeat.md`
- [ ] Write tests in `test/dataset_manager/dataset_repeat_test.exs`
- [ ] Implement `Dataset.repeat/2`
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "repeats dataset N times" do
  ds = Dataset.from_list([%{"x" => 1}])
  result = Dataset.repeat(ds, 3)

  assert Dataset.num_rows(result) == 3
end
```

---

### 1.4 Format.ImageFolder

- [ ] Read `04_imagefolder_format.md`
- [ ] Create test fixtures: `test/fixtures/imagefolder/`
- [ ] Write test file: `test/dataset_manager/format/imagefolder_test.exs`
- [ ] Create `lib/dataset_manager/format/imagefolder.ex`
- [ ] Register format in `lib/dataset_manager/format.ex`
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "loads images with labels from subdirectories" do
  {:ok, items} = ImageFolder.parse(@fixtures_path)

  assert length(items) > 0
  assert Enum.all?(items, &Map.has_key?(&1, "image"))
  assert Enum.all?(items, &Map.has_key?(&1, "label"))
end
```

---

## Phase 2: Core Infrastructure (Medium Complexity)

### 2.1 Export.Disk save_to_disk/load_from_disk

- [ ] Read `05_save_load_disk.md`
- [ ] Write tests: `test/dataset_manager/export/disk_test.exs`
- [ ] Create `lib/dataset_manager/export/disk.ex`
- [ ] Implement `save_dataset/2`
- [ ] Implement `load_dataset/2`
- [ ] Implement `save_dataset_dict/2`
- [ ] Implement `load_dataset_dict/2`
- [ ] Add convenience methods to `DatasetDict`
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "round-trips DatasetDict through disk" do
  original = sample_dataset_dict()
  path = tmp_path("test_dd")

  :ok = Export.Disk.save_dataset_dict(original, path)
  {:ok, loaded} = Export.Disk.load_dataset_dict(path)

  assert Map.keys(loaded.datasets) == Map.keys(original.datasets)
end
```

---

### 2.2 IterableDataset.interleave/2

- [ ] Read `06_iterable_interleave.md`
- [ ] Write tests: `test/dataset_manager/iterable_dataset_interleave_test.exs`
- [ ] Implement weighted random selection helper
- [ ] Implement `IterableDataset.interleave/2`
- [ ] Add stopping strategy support
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "interleaves with probabilities" do
  s1 = IterableDataset.from_stream(Stream.repeatedly(fn -> :a end))
  s2 = IterableDataset.from_stream(Stream.repeatedly(fn -> :b end))

  result = IterableDataset.interleave([s1, s2],
    probabilities: [0.8, 0.2],
    seed: 42
  )

  items = Enum.take(result, 100)
  a_count = Enum.count(items, & &1 == :a)

  # Should be roughly 80
  assert a_count > 60 and a_count < 95
end
```

---

### 2.3 Dataset.with_transform/set_transform

- [ ] Read `07_with_transform.md`
- [ ] Write tests: `test/dataset_manager/dataset_transform_test.exs`
- [ ] Add transform fields to Dataset struct
- [ ] Implement `set_transform/3`
- [ ] Implement `with_transform/3`
- [ ] Implement `reset_transform/1`
- [ ] Update Enumerable implementation
- [ ] Update Access implementation
- [ ] Run tests
- [ ] Run quality checks

**TDD Test Example**:
```elixir
test "applies transform on enumeration" do
  ds = Dataset.from_list([%{"x" => 1}])

  transformed = Dataset.set_transform(ds, fn item ->
    Map.put(item, "y", item["x"] * 2)
  end)

  [item] = Enum.to_list(transformed)
  assert item["y"] == 2
end
```

---

## Phase 3: Format Extensions

### 3.1 Format.XML

- [ ] Read `08_format_xml.md`
- [ ] Add `{:sweet_xml, "~> 0.7", optional: true}` to mix.exs
- [ ] Write tests: `test/dataset_manager/format/xml_test.exs`
- [ ] Create `lib/dataset_manager/format/xml.ex`
- [ ] Implement DOM parsing
- [ ] Implement SAX streaming (optional)
- [ ] Register format
- [ ] Run tests
- [ ] Run quality checks

---

### 3.2 Format.SQL

- [ ] Read `09_format_sql.md`
- [ ] Add `{:ecto_sql, "~> 3.10", optional: true}` to mix.exs
- [ ] Write tests: `test/dataset_manager/format/sql_test.exs`
- [ ] Create `lib/dataset_manager/format/sql.ex`
- [ ] Implement `from_query/3`
- [ ] Implement `from_table/3`
- [ ] Implement `stream_query/3`
- [ ] Run tests
- [ ] Run quality checks

---

### 3.3 Format.AudioFolder

- [ ] Read `10_audiofolder_format.md`
- [ ] Write tests: `test/dataset_manager/format/audiofolder_test.exs`
- [ ] Create `lib/dataset_manager/format/audiofolder.ex`
- [ ] Implement `parse/2`
- [ ] Implement `stream/2`
- [ ] Add `Dataset.from_audiofolder/2`
- [ ] Run tests
- [ ] Run quality checks

---

### 3.4 Format.WebDataset

- [ ] Read `11_webdataset_format.md`
- [ ] Write tests: `test/dataset_manager/format/webdataset_test.exs`
- [ ] Create `lib/dataset_manager/format/webdataset.ex`
- [ ] Implement tar extraction with `:erl_tar`
- [ ] Implement key-based grouping
- [ ] Implement streaming
- [ ] Run tests
- [ ] Run quality checks

---

## Phase 4: Additional Features (P2)

### 4.1 DatasetDict Column Operations

- [ ] Implement `DatasetDict.cast/2`
- [ ] Implement `DatasetDict.rename_column/3`
- [ ] Implement `DatasetDict.remove_columns/2`
- [ ] Write tests
- [ ] Run quality checks

### 4.2 IterableDataset Enhancements

- [ ] Implement `IterableDataset.cast/2`
- [ ] Implement `IterableDataset.rename_columns/2`
- [ ] Implement `IterableDataset.remove_columns/2`
- [ ] Implement `state_dict/1` for checkpointing
- [ ] Implement `load_state_dict/2`
- [ ] Write tests
- [ ] Run quality checks

### 4.3 Additional Dataset Operations

- [ ] Implement `Dataset.align_labels_with_mapping/3`
- [ ] Write tests
- [ ] Run quality checks

---

## Phase 5: Specialized Features (P3)

### 5.1 Index.Qdrant or Index.FAISS

- [ ] Research: Qdrant REST vs FAISS NIF
- [ ] Design API
- [ ] Write tests
- [ ] Implement
- [ ] Run quality checks

### 5.2 Index.Elasticsearch

- [ ] Add elasticsearch dependency (optional)
- [ ] Write tests
- [ ] Implement
- [ ] Run quality checks

### 5.3 Feature Types: Video, Pdf, Nifti

- [ ] Research required NIFs/libraries
- [ ] Design API
- [ ] Implement each type
- [ ] Write tests
- [ ] Run quality checks

### 5.4 Format.HDF5

- [ ] Research hdf5_ex or Python interop
- [ ] Design API
- [ ] Implement
- [ ] Write tests
- [ ] Run quality checks

---

## Validation Checklist

After each feature implementation:

- [ ] `mix test` - All tests pass
- [ ] `mix test --cover` - Coverage > 80%
- [ ] `mix format --check-formatted` - Code formatted
- [ ] `mix credo --strict` - No credo issues
- [ ] `mix dialyzer` - No type errors
- [ ] Documentation complete with examples
- [ ] CHANGELOG updated

---

## Commit Message Format

```
feat(module): add feature_name

- Implements Python datasets feature_name
- Adds X tests
- Closes #issue (if applicable)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

---

## Release Checklist

When ready for a release:

- [ ] All checklist items for target features complete
- [ ] `mix test` passes
- [ ] `mix docs` generates clean documentation
- [ ] Version bumped in `mix.exs`
- [ ] CHANGELOG.md updated
- [ ] README.md updated if needed
- [ ] Tag created: `git tag -a vX.Y.Z`
- [ ] Published: `mix hex.publish`

---

## Progress Tracking

| Date | Features Added | Coverage % | Notes |
|------|----------------|------------|-------|
| 2025-12-31 | v0.1.2 baseline | 66% | Gap analysis created |
| | | | |

---

## Reference: Python Feature Count

```
Category                    | Python | Elixir | Gap
----------------------------|--------|--------|-----
Dataset Methods             |     45 |     38 |   7
IterableDataset Methods     |     15 |      8 |   7
DatasetDict Methods         |     18 |     12 |   6
Feature Types               |     22 |     14 |   8
Input Formats               |     15 |      6 |   9
Export Formats              |      7 |      6 |   1
Formatters                  |      9 |      4 |   5
Hub Operations              |      6 |      4 |   2
Search/Index                |      8 |      4 |   4
----------------------------|--------|--------|-----
TOTAL                       |    145 |     96 |  49
```

Target: Close all 49 gaps for 100% parity.
