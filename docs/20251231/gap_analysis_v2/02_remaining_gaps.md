# Remaining Gaps - Technical Specifications

## P1 - High Priority

### 1. IterableDataset.interleave/2

**Purpose**: Interleave items from multiple IterableDatasets for diverse batches.

**Python Reference**:
```python
interleave_datasets([ds1, ds2], probabilities=[0.7, 0.3])
```

**Proposed Elixir API**:
```elixir
@spec interleave([IterableDataset.t()], keyword()) :: IterableDataset.t()
def interleave(datasets, opts \\ [])

# Options:
#   :probabilities - List of floats (must sum to 1.0)
#   :seed - Random seed
#   :stopping_strategy - :first_exhausted | :all_exhausted

# Example:
IterableDataset.interleave([ds1, ds2, ds3],
  probabilities: [0.5, 0.3, 0.2],
  seed: 42
)
```

**Implementation Notes**:
- Use Stream.resource/3 with weighted random selection
- Maintain separate iterators for each dataset
- Handle exhaustion per stopping_strategy

**Estimated Complexity**: Medium
**Dependencies**: None

---

### 2. IterableDataset.concatenate/1

**Purpose**: Concatenate multiple IterableDatasets sequentially.

**Proposed Elixir API**:
```elixir
@spec concatenate([IterableDataset.t()]) :: IterableDataset.t()
def concatenate(datasets)

# Example:
combined = IterableDataset.concatenate([train_stream, extra_data])
```

**Implementation Notes**:
- Use Stream.concat/1 internally
- Merge info from first dataset

**Estimated Complexity**: Low
**Dependencies**: None

---

### 3. DatasetDict.save_to_disk/2 and load_from_disk/2

**Purpose**: Persist and restore multi-split datasets.

**Python Reference**:
```python
dd.save_to_disk("./my_dataset")
dd = load_from_disk("./my_dataset")
```

**Proposed Elixir API**:
```elixir
@spec save_to_disk(DatasetDict.t(), Path.t(), keyword()) :: :ok | {:error, term()}
def save_to_disk(dd, path, opts \\ [])

@spec load_from_disk(Path.t(), keyword()) :: {:ok, DatasetDict.t()} | {:error, term()}
def load_from_disk(path, opts \\ [])
```

**Directory Structure**:
```
./my_dataset/
├── dataset_dict.json           # Split names and metadata
├── train/
│   ├── data-00000-of-00001.arrow
│   ├── dataset_info.json
│   └── state.json
└── test/
    ├── data-00000-of-00001.arrow
    ├── dataset_info.json
    └── state.json
```

**Implementation Notes**:
- Use existing Export.Arrow for data files
- JSON for metadata
- Maintain Python compatibility for interop

**Estimated Complexity**: Medium
**Dependencies**: Export.Arrow (exists)

---

### 4. DatasetDict.map/3 and filter/3

**Purpose**: Apply transformations across all splits.

**Proposed Elixir API**:
```elixir
@spec map(DatasetDict.t(), (map() -> map()), keyword()) :: DatasetDict.t()
def map(dd, fun, opts \\ [])

@spec filter(DatasetDict.t(), (map() -> boolean()), keyword()) :: DatasetDict.t()
def filter(dd, predicate, opts \\ [])

# Example:
dd = DatasetDict.map(dd, &tokenize/1)
dd = DatasetDict.filter(dd, &(&1.length > 10))
```

**Implementation Notes**:
- Apply to each split, collect results
- Preserve split names
- Consider parallel execution option

**Estimated Complexity**: Low
**Dependencies**: Dataset.map, Dataset.filter (exist)

---

### 5. Format.XML

**Purpose**: Parse XML documents into datasets.

**Python Reference**:
```python
load_dataset("xml", data_files="data.xml", field="item")
```

**Proposed Elixir API**:
```elixir
@spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
def parse(path, opts \\ [])

# Options:
#   :row_tag - Element tag for rows (default: "row")
#   :encoding - Character encoding

# Example:
{:ok, items} = Format.XML.parse("data.xml", row_tag: "item")
```

**Implementation Notes**:
- Use SweetXml for parsing
- Stream large files with SAX parser
- Handle nested structures

**Estimated Complexity**: Medium
**Dependencies**: `sweet_xml` hex package

---

### 6. Format.SQL

**Purpose**: Load data from SQL databases.

**Proposed Elixir API**:
```elixir
@spec from_query(Ecto.Repo.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
def from_query(repo, sql, opts \\ [])

@spec from_table(Ecto.Repo.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
def from_table(repo, table_name, opts \\ [])

# Example:
{:ok, items} = Format.SQL.from_query(MyApp.Repo, "SELECT * FROM users WHERE active = true")
```

**Implementation Notes**:
- Use Ecto.Adapters.SQL.query!
- Support parameterized queries
- Handle large results with streaming

**Estimated Complexity**: Medium
**Dependencies**: `ecto_sql` (optional dependency)

---

## P2 - Medium Priority

### 7. Dataset.repeat/2

**Purpose**: Repeat dataset N times.

**Proposed Elixir API**:
```elixir
@spec repeat(t(), pos_integer()) :: t()
def repeat(dataset, num_times)

# Example:
augmented = Dataset.repeat(dataset, 3)  # 3x the items
```

**Implementation Notes**:
- Simple: `List.duplicate(items, n) |> List.flatten()`
- Consider lazy version for IterableDataset

**Estimated Complexity**: Low
**Dependencies**: None

---

### 8. Dataset.with_transform/3 and set_transform/3

**Purpose**: Apply transforms lazily on access.

**Proposed Elixir API**:
```elixir
@spec with_transform(t(), (map() -> map()), keyword()) :: t()
def with_transform(dataset, transform, opts \\ [])

@spec set_transform(t(), (map() -> map()), keyword()) :: t()
def set_transform(dataset, transform, opts \\ [])

# Example:
ds = Dataset.with_transform(ds, &augment/1)
for item <- ds do
  # item is augmented on-the-fly
end
```

**Implementation Notes**:
- Store transform function in struct
- Apply in Enumerable.reduce/3
- Stack multiple transforms

**Estimated Complexity**: Medium
**Dependencies**: None

---

### 9. Format.ImageFolder

**Purpose**: Load image datasets from directory structure.

**Directory Structure**:
```
data/
├── cat/
│   ├── 001.jpg
│   └── 002.jpg
└── dog/
    ├── 001.jpg
    └── 002.jpg
```

**Proposed Elixir API**:
```elixir
@spec parse(Path.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
def parse(path, opts \\ [])

# Returns:
[
  %{"image" => %{path: "...", bytes: <<...>>}, "label" => "cat"},
  %{"image" => %{path: "...", bytes: <<...>>}, "label" => "dog"}
]
```

**Implementation Notes**:
- Use Path.wildcard for discovery
- Support common image extensions
- Option to decode or keep raw bytes

**Estimated Complexity**: Low
**Dependencies**: None

---

### 10. Format.AudioFolder

**Purpose**: Same as ImageFolder for audio files.

**Implementation Notes**:
- Reuse ImageFolder pattern
- Support .wav, .mp3, .flac extensions

**Estimated Complexity**: Low
**Dependencies**: None

---

## P3 - Low Priority

### 11. Index.FAISS (NIF)

**Purpose**: High-performance vector similarity search.

**Options**:
1. **Rustler NIF**: Wrap faiss-rs
2. **Port**: External Python FAISS service
3. **External Service**: Use Qdrant/Milvus via REST

**Recommendation**: Start with Qdrant integration (REST API) before investing in NIF.

**Estimated Complexity**: High
**Dependencies**: Rustler or external service

---

### 12. Index.Elasticsearch

**Purpose**: Full-text search capability.

**Proposed Elixir API**:
```elixir
@spec new(String.t(), keyword()) :: t()
def new(column, opts \\ [])

@spec index(t(), [map()]) :: :ok
def index(index, documents)

@spec search(t(), String.t(), keyword()) :: {[float()], [integer()]}
def search(index, query, opts \\ [])
```

**Implementation Notes**:
- Use `elasticsearch` or `elastix` hex package
- Bulk indexing for efficiency
- Connection pooling

**Estimated Complexity**: Medium
**Dependencies**: `elasticsearch` or `elastix`

---

### 13. Feature Types: Video, Pdf, Nifti

**Purpose**: Specialized media handling.

**Video**:
- Decode with evision or FFmpeg NIF
- Return frames as Nx tensors

**Pdf**:
- Use Poppler NIF or external tool
- Return page images or extracted text

**Nifti** (Medical Imaging):
- Pure Elixir parser for NIfTI format
- Return 3D/4D voxel data as Nx tensor

**Estimated Complexity**: High (each)
**Dependencies**: External libraries/NIFs

---

### 14. Format.WebDataset

**Purpose**: Load tar archives where samples are grouped by key.

**Archive Structure**:
```
sample001.jpg
sample001.txt
sample002.jpg
sample002.txt
```

**Proposed Elixir API**:
```elixir
@spec parse_stream(Path.t(), keyword()) :: Enumerable.t()
def parse_stream(tar_path, opts \\ [])

# Returns stream of:
%{"__key__" => "sample001", "jpg" => <<...>>, "txt" => "..."}
```

**Implementation Notes**:
- Use :erl_tar for extraction
- Group files by key prefix
- Stream processing for large archives

**Estimated Complexity**: Medium
**Dependencies**: None (Erlang :erl_tar)

---

### 15. Format.HDF5

**Purpose**: Scientific data format support.

**Options**:
1. **hdf5_ex**: If available
2. **Custom NIF**: Wrap HDF5 C library
3. **Python Interop**: Call h5py via Port

**Estimated Complexity**: High
**Dependencies**: HDF5 C library or Python

---

## Implementation Priority Matrix

| Gap | Complexity | Value | Dependencies | Recommended Order |
|-----|------------|-------|--------------|-------------------|
| DatasetDict.map/filter | Low | High | None | 1 |
| IterableDataset.concatenate | Low | High | None | 2 |
| Dataset.repeat | Low | Medium | None | 3 |
| Format.ImageFolder | Low | High | None | 4 |
| DatasetDict.save/load | Medium | High | Export.Arrow | 5 |
| IterableDataset.interleave | Medium | High | None | 6 |
| with/set_transform | Medium | Medium | None | 7 |
| Format.XML | Medium | Medium | sweet_xml | 8 |
| Format.SQL | Medium | Medium | ecto_sql | 9 |
| Format.AudioFolder | Low | Medium | None | 10 |
| Index.Qdrant | Medium | Medium | HTTP | 11 |
| Format.WebDataset | Medium | Low | None | 12 |
| Index.Elasticsearch | Medium | Low | elasticsearch | 13 |
| Video/Pdf/Nifti | High | Low | NIFs | 14+ |
| Index.FAISS | High | Low | Rustler | 15+ |
| Format.HDF5 | High | Low | HDF5 lib | 16+ |
