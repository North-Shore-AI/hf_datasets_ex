# Claude Code Instructions

## Priority Task

**Run the 11 gap implementation prompts** in `docs/20251231/gap_analysis_v2/prompts/`

```bash
./docs/20251231/gap_analysis_v2/prompts/run-prompts.sh
```

Or manually:
```bash
claude -p "$(cat docs/20251231/gap_analysis_v2/prompts/01_dataset_dict_ops.md)"
```

Each prompt is TDD-style with tests to write first.
