# Repository Guidelines

## Project Structure & Module Organization
`cmd/eth-indexer` contains the entrypoint. Core indexing logic lives in `core/`, orchestration and query services in `service/`, HTTP handlers and server setup in `api/`, config loading in `config/`, and persistence adapters in `storage/`. Chain scanning code sits in `scanner/`. Root-level docs such as `README.md`, `PROJECT_SUMMARY.md`, and the implementation plans describe intended behavior; keep them aligned with code changes.

## Build, Test, and Development Commands
Use `make build` to compile `bin/eth-indexer`, `make run` to start the service locally, and `make test` to run the full Go test suite. `make fmt` applies standard Go formatting, `make lint` runs `golangci-lint`, and `make deps` refreshes module dependencies with `go mod download` and `go mod tidy`. For container workflows, use `make docker-build`, `make docker-up`, and `make docker-down`.

## Coding Style & Naming Conventions
Follow idiomatic Go: tabs for indentation, exported identifiers in `PascalCase`, internal helpers in `camelCase`, and package names in short lowercase form such as `api` or `storage`. Keep files focused on one responsibility. Run `make fmt` before submitting changes; treat `golangci-lint` findings as blockers. Prefer descriptive constructor names like `NewIndexerService` and test names in the `TestType_Method` style.

## Testing Guidelines
Tests use Go’s `testing` package and live next to the code, for example [`storage/state_storage_test.go`](/Users/hoseok/mytools/eth-indexer/storage/state_storage_test.go). Add table-driven tests for new branches and error paths, especially around RPC, storage, and config parsing. Run `make test` locally before opening a PR. There is no formal coverage gate yet, but new behavior should ship with regression tests.

## Commit & Pull Request Guidelines
This repository currently has no commit history, so adopt Conventional Commits going forward: `feat: add bulk retry handling`, `fix: guard empty event list`. Keep commits scoped to one change. PRs should include a short description, linked issue or task when available, config or schema changes, and sample requests/responses or logs for API-impacting work.

## Configuration & Security Tips
Start from `.env.example` or `config.example.json`; never commit real RPC credentials, private endpoints, or production ABI files. Validate changes that affect OpenSearch mappings or block confirmation depth in a local or staging environment before rolling them out.
