package storage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewSimpleStateStorage(t *testing.T) {
	tests := []struct {
		name        string
		setupPath   func(t *testing.T) string
		wantErr     bool
		errContains string
		validate    func(t *testing.T, path string)
	}{
		{
			name: "creates file and parent directories",
			setupPath: func(t *testing.T) string {
				return filepath.Join(t.TempDir(), "nested", "dirs", "state.json")
			},
			wantErr: false,
			validate: func(t *testing.T, path string) {
				// Check that file was created
				if _, err := os.Stat(path); os.IsNotExist(err) {
					t.Errorf("File was not created: %s", path)
				}

				// Check that parent directories were created
				dir := filepath.Dir(path)
				if _, err := os.Stat(dir); os.IsNotExist(err) {
					t.Errorf("Parent directories were not created: %s", dir)
				}

				// Check file content is empty JSON object
				content, err := os.ReadFile(path)
				if err != nil {
					t.Fatalf("Failed to read created file: %v", err)
				}
				if string(content) != "{}" {
					t.Errorf("File content = %s, want {}", string(content))
				}
			},
		},
		{
			name: "works with existing file",
			setupPath: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "state.json")
				// Create file first
				os.WriteFile(path, []byte(`{"Transfer": 1000}`), 0644)
				return path
			},
			wantErr: false,
			validate: func(t *testing.T, path string) {
				// Check that existing file content is preserved
				content, err := os.ReadFile(path)
				if err != nil {
					t.Fatalf("Failed to read file: %v", err)
				}
				if string(content) != `{"Transfer": 1000}` {
					t.Errorf("File content was modified: %s", string(content))
				}
			},
		},
		{
			name: "creates deeply nested directories",
			setupPath: func(t *testing.T) string {
				return filepath.Join(t.TempDir(), "a", "b", "c", "d", "e", "state.json")
			},
			wantErr: false,
			validate: func(t *testing.T, path string) {
				if _, err := os.Stat(path); os.IsNotExist(err) {
					t.Errorf("File was not created: %s", path)
				}
			},
		},
		{
			name: "invalid file extension",
			setupPath: func(t *testing.T) string {
				return filepath.Join(t.TempDir(), "state.txt")
			},
			wantErr:     true,
			errContains: "must be a .json file",
		},
		{
			name: "creates file in current directory",
			setupPath: func(t *testing.T) string {
				return filepath.Join(t.TempDir(), "state.json")
			},
			wantErr: false,
			validate: func(t *testing.T, path string) {
				if _, err := os.Stat(path); os.IsNotExist(err) {
					t.Errorf("File was not created: %s", path)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := tt.setupPath(t)

			storage, err := NewSimpleStateStorage(path)

			if tt.wantErr {
				if err == nil {
					t.Errorf("NewSimpleStateStorage() error = nil, wantErr = true")
					return
				}
				if tt.errContains != "" && !contains(err.Error(), tt.errContains) {
					t.Errorf("NewSimpleStateStorage() error = %v, should contain %q", err, tt.errContains)
				}
				return
			}

			if err != nil {
				t.Errorf("NewSimpleStateStorage() unexpected error = %v", err)
				return
			}

			if storage == nil {
				t.Error("NewSimpleStateStorage() returned nil storage")
				return
			}

			if tt.validate != nil {
				tt.validate(t, path)
			}
		})
	}
}

func TestSimpleStateStorage_Get(t *testing.T) {
	tests := []struct {
		name        string
		setupFile   func(t *testing.T) string
		want        map[string]uint64
		wantErr     bool
		errContains string
	}{
		{
			name: "successful read with valid data",
			setupFile: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "state.json")
				storage, _ := NewSimpleStateStorage(path)
				storage.Set(map[string]uint64{"Transfer": 1000000, "Approval": 2000000})
				return path
			},
			want: map[string]uint64{
				"Transfer": 1000000,
				"Approval": 2000000,
			},
			wantErr: false,
		},
		{
			name: "empty json object",
			setupFile: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "state.json")
				os.WriteFile(path, []byte(`{}`), 0644)
				return path
			},
			want:    map[string]uint64{},
			wantErr: false,
		},
		{
			name: "file is empty",
			setupFile: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "state.json")
				os.WriteFile(path, []byte(""), 0644)
				return path
			},
			want:        nil,
			wantErr:     true,
			errContains: "expected",
		},
		{
			name: "file does not exist",
			setupFile: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "nonexistent.json")
				// Don't create the file, but create the storage
				NewSimpleStateStorage(path)
				// Then delete it
				os.Remove(path)
				return path
			},
			want:    map[string]uint64{},
			wantErr: false, // Returns empty map, not error
		},
		{
			name: "number format (from Set method)",
			setupFile: func(t *testing.T) string {
				path := filepath.Join(t.TempDir(), "state.json")
				storage, _ := NewSimpleStateStorage(path)
				storage.Set(map[string]uint64{"Transfer": 5000000})
				return path
			},
			want: map[string]uint64{
				"Transfer": 5000000,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := tt.setupFile(t)
			storage, _ := NewSimpleStateStorage(path)

			got, err := storage.Get()

			if tt.wantErr {
				if err == nil {
					t.Errorf("Get() error = nil, wantErr = true")
					return
				}
				if tt.errContains != "" && !contains(err.Error(), tt.errContains) {
					t.Errorf("Get() error = %v, should contain %q", err, tt.errContains)
				}
				return
			}

			if err != nil {
				t.Errorf("Get() unexpected error = %v", err)
				return
			}

			if len(got) != len(tt.want) {
				t.Errorf("Get() returned %d items, want %d", len(got), len(tt.want))
				return
			}

			for key, wantVal := range tt.want {
				gotVal, ok := got[key]
				if !ok {
					t.Errorf("Get() missing key %q", key)
					continue
				}
				if gotVal != wantVal {
					t.Errorf("Get()[%q] = %d, want %d", key, gotVal, wantVal)
				}
			}
		})
	}
}

func TestSimpleStateStorage_Set(t *testing.T) {
	tests := []struct {
		name    string
		state   map[string]uint64
		wantErr bool
	}{
		{
			name: "set single event",
			state: map[string]uint64{
				"Transfer": 1000000,
			},
			wantErr: false,
		},
		{
			name: "set multiple events",
			state: map[string]uint64{
				"Transfer": 1000000,
				"Approval": 2000000,
				"Mint":     3000000,
			},
			wantErr: false,
		},
		{
			name:    "set empty state",
			state:   map[string]uint64{},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "state.json")
			storage, _ := NewSimpleStateStorage(path)

			err := storage.Set(tt.state)

			if tt.wantErr {
				if err == nil {
					t.Errorf("Set() error = nil, wantErr = true")
				}
				return
			}

			if err != nil {
				t.Errorf("Set() unexpected error = %v", err)
				return
			}

			// Read back and verify
			got, err := storage.Get()
			if err != nil {
				t.Errorf("Get() after Set() failed: %v", err)
				return
			}

			if len(got) != len(tt.state) {
				t.Errorf("After Set(), Get() returned %d items, want %d", len(got), len(tt.state))
			}

			for key, wantVal := range tt.state {
				gotVal, ok := got[key]
				if !ok {
					t.Errorf("After Set(), Get() missing key %q", key)
					continue
				}
				if gotVal != wantVal {
					t.Errorf("After Set(), Get()[%q] = %d, want %d", key, gotVal, wantVal)
				}
			}
		})
	}
}

// Helper function to check if string contains substring
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 ||
		(len(s) > 0 && len(substr) > 0 && containsSubstr(s, substr)))
}

func containsSubstr(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
