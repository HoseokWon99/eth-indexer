# PostgreSQL to MongoDB Migration Plan

---

## 1. Why MongoDB Fits This Project

Your `event_records` table is essentially a **document store** already — a flat schema with a JSONB `data` column, no joins, no foreign keys, append-only writes with `ON CONFLICT DO NOTHING`. MongoDB is a natural fit.

---

## 2. Schema Mapping

| PostgreSQL | MongoDB |
|---|---|
| `event_records` table | `event_records` collection |
| PK `(tx_hash, log_index)` | Unique index on `{tx_hash: 1, log_index: 1}` |
| JSONB `data` column | Native embedded document `data` field |
| `TIMESTAMPTZ timestamp` | `ISODate` timestamp |
| `BIGINT block_number` | `NumberLong` / `int64` |

**Document structure:**
```json
{
  "_id": "tx_hash:log_index",
  "topic": "Transfer",
  "contract_address": "0x5Fb...",
  "tx_hash": "0xabc...",
  "block_hash": "0xdef...",
  "block_number": NumberLong(12345),
  "log_index": NumberLong(0),
  "data": { "from": "0x...", "to": "0x...", "value": "1000" },
  "timestamp": ISODate("2026-03-27T...")
}
```

---

### 3. Index Migration

Create these indexes to match current query patterns:

```javascript
// Unique constraint (replaces PK)
db.event_records.createIndex({ tx_hash: 1, log_index: 1 }, { unique: true })

// Single-field indexes
db.event_records.createIndex({ topic: 1 })
db.event_records.createIndex({ contract_address: 1 })
db.event_records.createIndex({ block_number: -1 })
db.event_records.createIndex({ block_hash: 1 })
db.event_records.createIndex({ timestamp: -1 })

// Composite indexes (common query patterns)
db.event_records.createIndex({ topic: 1, block_number: -1 })
db.event_records.createIndex({ topic: 1, contract_address: 1 })

// No GIN equivalent needed — MongoDB natively queries nested documents
```

---

### 4. Files to Change

#### A. Shared library: `libs/config/`

| Action | File | Details |
|---|---|---|
| **New** | `libs/config/mongo.go` | `MongoOptions`, `LoadMongoFromEnv()`, `CreateMongoClient()` using `go.mongodb.org/mongo-driver/v2/mongo` |
| **Remove** | `libs/config/postgres.go` | Delete `PostgresOptions`, `CreatePgConnPool` |

**Env vars change:**
```
POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
  →  MONGO_URI, MONGO_DB
```

#### B. Indexer service: `services/indexer/`

| Action | File | Details |
|---|---|---|
| **Rewrite** | `storage/event_records_storage.go` | Replace pgx batch insert with `mongo.Collection.BulkWrite` using `UpdateOne` + `upsert:true` (idempotent) |
| **Delete** | `storage/migrate.go` + `migrations/001_init_schema.sql` | MongoDB is schemaless; create indexes on startup instead |
| **New** | `storage/indexes.go` | `EnsureIndexes(col *mongo.Collection)` — runs `CreateMany` with the indexes listed above |
| **Update** | `core/storage.go` | Drop `topic string` param from `SaveAll` — `record.Topic` already carries it |
| **Update** | `main.go` | Replace `CreatePgConnPool` + `Migrate` with `CreateMongoClient` + `EnsureIndexes` |

**Interface change:**

```go
// Before
SaveAll(ctx context.Context, topic string, records []common.EventRecord) error

// After
SaveAll(ctx context.Context, records []common.EventRecord) error
```

**Key write logic change:**

```go
// Before (pgx batch)
batch.Queue(insertSQL, params, columnTypes, nil)

// After (mongo bulk write) — topic comes from record.Topic
models = append(models, mongo.NewUpdateOneModel().
    SetFilter(bson.D{{"tx_hash", r.TxHash}, {"log_index", r.LogIndex}}).
    SetUpdate(bson.D{{"$setOnInsert", doc}}).
    SetUpsert(true))
col.BulkWrite(ctx, models)
```

`$setOnInsert` + `upsert` gives the same idempotent behavior as `ON CONFLICT DO NOTHING`.

#### C. API server: `services/api-server/`

| Action | File | Details |
|---|---|---|
| **Rewrite** | `storage/event_records_storage.go` | Replace squirrel query builder with `mongo.Collection.Find` + `bson.D` filter construction |
| **Update** | `main.go` | Replace `CreatePgConnPool` with `CreateMongoClient` |

**Key query logic change:**

```go
// Before (squirrel)
sq.Select("*").From("event_records").Where(sq.Eq{"topic": topic})

// After (mongo)
filter := bson.D{{"topic", topic}}
opts := options.Find().SetSort(bson.D{{"block_number", 1}, {"log_index", 1}})
cursor, _ := col.Find(ctx, filter, opts)
```

**Filter mapping:**

| PostgreSQL (squirrel) | MongoDB (bson) |
|---|---|
| `sq.Eq{"column": val}` | `bson.E{"column", val}` |
| `sq.Eq{"column": []val}` | `bson.E{"column", bson.D{{"$in", vals}}}` |
| `sq.Lt{"column": val}` | `bson.E{"column", bson.D{{"$lt", val}}}` |
| `sq.GtOrEq{"column": val}` | `bson.E{"column", bson.D{{"$gte", val}}}` |
| `data @> '{"key":"val"}'` | `bson.E{"data.key", "val"}` (dot notation — simpler!) |

#### D. No changes needed

- `libs/common/types.go`, `domain.go` — `ComparisonFilter`, `PagingOptions` are DB-agnostic; `EventRecord.Topic` field already added ✓
- `services/api-server/types/types.go` — filter/cursor types are DB-agnostic
- `services/api-server/storage/cache_storage.go` — Redis layer untouched
- `services/indexer/storage/state_storage.go` — file-based, no DB involvement
- `services/indexer/core/`, `services/api-server/core/` — interfaces only, no DB dependency
- `services/dashboard/` — Kafka consumer, no direct DB access

---

### 5. Go Dependencies

```
# Remove
github.com/jackc/pgx
github.com/Masterminds/squirrel

# Add
go.mongodb.org/mongo-driver/v2
```

---

### 6. Docker Compose Changes

Replace the `postgres` service:

```yaml
mongo:
  image: mongo:7
  container_name: eth-indexer-test-database
  environment:
    MONGO_INITDB_DATABASE: eth_indexer
  ports:
    - "27017:27017"
  networks:
    - eth-indexer-test
  healthcheck:
    test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
    interval: 5s
    timeout: 5s
    retries: 5
```

Update all indexer/api-server env vars from `POSTGRES_*` to `MONGO_URI` / `MONGO_DB`.

**CDC impact:** Debezium currently captures PostgreSQL WAL changes. For MongoDB, switch to the [Debezium MongoDB connector](https://debezium.io/documentation/reference/stable/connectors/mongodb.html) which uses MongoDB change streams. Update `debezium-init` and `kafka-connect` config accordingly.

---

### 7. Kubernetes Changes

| File | Change |
|---|---|
| `k8s/secrets.yaml` | Replace Postgres credentials with `MONGO_URI` |
| `k8s/indexer/` | Update ConfigMap env vars |
| `k8s/api-server/` | Update ConfigMap env vars |
| `k8s/kafka-connect/` | Update Debezium connector config for MongoDB |
| `k8s/external-services.yaml` | Point to MongoDB instead of PostgreSQL |

---

### 8. Execution Order

1. ~~Add `EventRecord.Topic` field~~ ✓ done
2. Add `go.mongodb.org/mongo-driver/v2` dependency 
3. Create `libs/config/mongo.go` (connection helper)
4. Create `services/indexer/storage/indexes.go` (index setup)
5. Update `services/indexer/core/storage.go` — drop `topic` param from `SaveAll`
6. Rewrite `services/indexer/storage/event_records_storage.go` (bulk upsert, use `record.Topic`)
7. Update `services/indexer/core/indexer.go` — remove `sc.EventName()` arg from `SaveAll` call
8. Update `services/indexer/main.go`
9. Rewrite `services/api-server/storage/event_records_storage.go` (query builder)
10. Update `services/api-server/main.go`
11. Update `docker-compose.local.yml` (mongo service + env vars)
12. Update Debezium config for MongoDB change streams
13. Update Kubernetes manifests
14. Remove pgx/squirrel dependencies, delete migration files
15. Test end-to-end

Want me to start implementing any of these steps?