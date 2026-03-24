package storage

import (
	_ "embed"

	"github.com/jackc/pgx"
)

//go:embed migrations/001_init_schema.sql
var migrationSQL string

// Migrate runs the schema migration against the given connection pool.
// All statements use IF NOT EXISTS so it is safe to run on every startup.
func Migrate(pool *pgx.ConnPool) error {
	_, err := pool.Exec(migrationSQL)
	return err
}
