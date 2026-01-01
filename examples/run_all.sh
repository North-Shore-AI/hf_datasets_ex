#!/bin/bash
# Run all HfDatasetsEx examples
# Usage: ./examples/run_all.sh [--live]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

for arg in "$@"; do
  case "$arg" in
    --live)
      export HF_DATASETS_EX_LIVE_EXAMPLES=1
      ;;
    --help|-h)
      echo "Usage: ./examples/run_all.sh [--live]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: ./examples/run_all.sh [--live]"
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "HfDatasetsEx Examples"
echo "============================================================"
echo ""

if [ -z "${HF_DATASETS_EX_LIVE_EXAMPLES}" ]; then
  echo "Live HuggingFace examples are disabled by default."
  echo "Set HF_DATASETS_EX_LIVE_EXAMPLES=1 or pass --live to run against live datasets."
  echo ""
  exit 0
fi

if [ -z "${HF_TOKEN}" ]; then
  echo "HF_TOKEN is not set; gated datasets may be skipped or fail to load."
  echo ""
fi

# Core functionality examples
CORE_EXAMPLES=(
  "examples/basic_usage.exs"
  "examples/load_dataset_example.exs"
  "examples/dataset_dict_example.exs"
  "examples/streaming_example.exs"
  "examples/vision/vision_example.exs"
  "examples/sampling_strategies.exs"
  "examples/cross_validation.exs"
)

# v0.1.2 File I/O examples (no network required)
FILE_IO_EXAMPLES=(
  "examples/file_loading.exs"
  "examples/export_formats.exs"
)

# v0.1.2 ML integration examples (no network required)
ML_EXAMPLES=(
  "examples/nx_formatting.exs"
  "examples/vector_search.exs"
  "examples/type_casting.exs"
  "examples/custom_builder.exs"
)

# Hub examples (requires HF_TOKEN)
HUB_EXAMPLES=(
  "examples/hub_push.exs"
)

# Dataset-specific examples (requires network)
DATASET_EXAMPLES=(
  "examples/math/gsm8k_example.exs"
  "examples/math/math500_example.exs"
  "examples/chat/tulu3_sft_example.exs"
  "examples/preference/hh_rlhf_example.exs"
  "examples/code/deepcoder_example.exs"
)

run_example() {
  local example=$1
  echo ""
  echo "------------------------------------------------------------"
  echo "Running: $example"
  echo "------------------------------------------------------------"
  mix run "$example"
  echo ""
}

echo "=== File I/O Examples (v0.1.2+) ==="
for example in "${FILE_IO_EXAMPLES[@]}"; do
  if [ -f "$example" ]; then
    run_example "$example"
  else
    echo "Skipping $example (not found)"
  fi
done

echo "=== ML Integration Examples (v0.1.2+) ==="
for example in "${ML_EXAMPLES[@]}"; do
  if [ -f "$example" ]; then
    run_example "$example"
  else
    echo "Skipping $example (not found)"
  fi
done

echo "=== Hub Examples ==="
for example in "${HUB_EXAMPLES[@]}"; do
  if [ -f "$example" ]; then
    run_example "$example"
  else
    echo "Skipping $example (not found)"
  fi
done

echo "=== Core Functionality Examples ==="
for example in "${CORE_EXAMPLES[@]}"; do
  if [ -f "$example" ]; then
    run_example "$example"
  else
    echo "Skipping $example (not found)"
  fi
done

echo "=== Dataset-Specific Examples ==="
for example in "${DATASET_EXAMPLES[@]}"; do
  if [ -f "$example" ]; then
    run_example "$example"
  else
    echo "Skipping $example (not found)"
  fi
done

echo "============================================================"
echo "All examples completed!"
echo "============================================================"
