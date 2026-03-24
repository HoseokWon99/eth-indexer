package config

import (
	"crypto/x509"
	"fmt"
	"os"
)

func CreateCertPool(filepath string) (*x509.CertPool, error) {
	ca, err := os.ReadFile(filepath)
	if err != nil {
		return nil, err
	}
	certPool := x509.NewCertPool()
	if !certPool.AppendCertsFromPEM(ca) {
		return nil, fmt.Errorf("failed to append CA certificate")
	}
	return certPool, nil
}
