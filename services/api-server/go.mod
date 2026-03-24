module eth-indexer.dev/services/api-server

go 1.24.0

require (
	eth-indexer.dev/libs/common v0.0.0
	eth-indexer.dev/libs/config v0.0.0
	github.com/Masterminds/squirrel v1.5.4
	github.com/jackc/pgx v3.6.2+incompatible
	github.com/redis/go-redis/v9 v9.18.0
)

replace eth-indexer.dev/libs/common => ../../libs/common

replace eth-indexer.dev/libs/config => ../../libs/config