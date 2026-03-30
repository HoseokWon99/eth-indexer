# Multi-ABI Indexer Plan

**New architecture:**
```
Indexer → Worker[] (per ABI, parallel) → Scanner[] (per event, parallel)
```

**4 changes, 1 new file:**

| File | Change |
|------|--------|
| `config/config.go` | Add `WorkerConfig`, replace single-ABI fields with `Workers []WorkerConfig`, load from numbered `INDEXER_WORKER_N_*` env vars |
| `core/worker.go` | **NEW** — `Worker` struct + `IndexBlock()`, moves scanner goroutine logic here, uses `workerName:eventName` state keys |
| `core/indexer.go` | Replace `[]Scanner` with `[]*Worker`; `indexAll` dispatches to workers |
| `main.go` | Build workers from config; collect composite state keys for `SimpleStateStorage` |

**Key design choices:**
- `Scanner` interface and `EventRecordsScanner` are **untouched**
- `StateStorage` is **untouched** — composite keys like `erc20:Transfer` are treated as opaque strings
- Breaking change: old env vars removed, existing state files need one-time migration

Does this plan look right, or would you like to adjust anything (e.g., backward compat with old env vars, a different config format)?