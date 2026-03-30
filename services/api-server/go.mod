module eth-indexer.dev/services/api-server

go 1.25.0

require (
	eth-indexer.dev/libs/common v0.0.0
	eth-indexer.dev/libs/config v0.0.0
	github.com/Masterminds/squirrel v1.5.4
	github.com/jackc/pgx v3.6.2+incompatible
	github.com/redis/go-redis/v9 v9.18.0
	go.mongodb.org/mongo-driver/v2 v2.5.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/klauspost/compress v1.17.6 // indirect
	github.com/lann/builder v0.0.0-20180802200727-47ae307949d0 // indirect
	github.com/lann/ps v0.0.0-20150810152359-62de8c46ede0 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/xdg-go/pbkdf2 v1.0.0 // indirect
	github.com/xdg-go/scram v1.2.0 // indirect
	github.com/xdg-go/stringprep v1.0.4 // indirect
	github.com/youmark/pkcs8 v0.0.0-20240726163527-a2c0da244d78 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	golang.org/x/crypto v0.49.0 // indirect
	golang.org/x/sync v0.20.0 // indirect
	golang.org/x/text v0.35.0 // indirect
)

replace eth-indexer.dev/libs/common => ../../libs/common

replace eth-indexer.dev/libs/config => ../../libs/config
