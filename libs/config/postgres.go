package config

import (
	"crypto/tls"
	"fmt"
	"os"
	"strconv"

	"github.com/jackc/pgx"
)

type PostgresOptions struct {
	Host           string
	Port           uint16
	Database       string
	User           string
	Password       string
	MaxConnections int
	CACertPath     string
}

func LoadPostgresFromEnv() (*PostgresOptions, error) {
	portStr := GetEnv("POSTGRES_PORT", "5432")
	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		return nil, fmt.Errorf("invalid POSTGRES_PORT: %w", err)
	}
	maxConnStr := GetEnv("POSTGRES_MAX_CONNECTIONS", "10")
	maxConn, err := strconv.Atoi(maxConnStr)
	if err != nil {
		return nil, fmt.Errorf("invalid POSTGRES_MAX_CONNECTIONS: %w", err)
	}
	return &PostgresOptions{
		Host:           os.Getenv("POSTGRES_HOST"),
		Port:           uint16(port),
		Database:       os.Getenv("POSTGRES_DB"),
		User:           os.Getenv("POSTGRES_USER"),
		Password:       os.Getenv("POSTGRES_PASSWORD"),
		MaxConnections: maxConn,
		CACertPath:     os.Getenv("POSTGRES_CA_CERT_PATH"),
	}, nil
}

func CreatePgConnPool(options *PostgresOptions) (*pgx.ConnPool, error) {
	pgConfig := pgx.ConnConfig{
		Host:     options.Host,
		Port:     options.Port,
		Database: options.Database,
		User:     options.User,
		Password: options.Password,
	}
	if len(options.CACertPath) > 0 {
		certPool, err := CreateCertPool(options.CACertPath)
		if err != nil {
			return nil, err
		}
		pgConfig.TLSConfig = &tls.Config{
			RootCAs: certPool,
		}
	}
	return pgx.NewConnPool(pgx.ConnPoolConfig{
		ConnConfig:     pgConfig,
		MaxConnections: options.MaxConnections,
	})
}
