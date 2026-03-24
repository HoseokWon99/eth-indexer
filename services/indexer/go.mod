module eth-indexer.dev/services/indexer

go 1.24.0

require (
	eth-indexer.dev/libs/common v0.0.0
	eth-indexer.dev/libs/config v0.0.0
	github.com/ethereum/go-ethereum v1.17.0
	github.com/goccy/go-json v0.10.5
	github.com/jackc/pgx v3.6.2+incompatible
	golang.org/x/sync v0.19.0
)

replace eth-indexer.dev/libs/common => ../../libs/common

replace eth-indexer.dev/libs/config => ../../libs/config