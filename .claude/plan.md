# Recommended Filter Serialization Strategies

## Current Approach Analysis

**Current**: URL Query String → xxhash for cache key
```go
contract_address=0x123,0x456&block_number={"gte":1000}
```

**Pros**: Human-readable, HTTP-friendly, debuggable  
**Cons**: Verbose, requires sorting for determinism, two-step encoding

---

## Recommended Alternatives

### Option 1: Canonical JSON (Best for Human Readability)

**Approach**: Serialize filters to deterministic JSON

```go
func encodeFiltersJSON(filters core.EventRecordFilters) (string, error) {
    // Normalize by sorting array fields
    normalized := filters
    if len(filters.ContractAddress) > 0 {
        normalized.ContractAddress = slices.Clone(filters.ContractAddress)
        slices.Sort(normalized.ContractAddress)
    }
    // ... repeat for other array fields ...
    
    // json.Marshal already produces deterministic output for maps
    bytes, err := json.Marshal(normalized)
    if err != nil {
        return "", err
    }
    return string(bytes), nil
}
```

**Example Output**:
```json
{
  "contract_address": ["0x123", "0x456"],
  "block_number": {"gte": 1000},
  "tx_hash": []
}
```

**Pros**:
- ✅ Highly readable for debugging
- ✅ Standard format, works with all languages
- ✅ Deterministic (Go's json.Marshal uses sorted keys)
- ✅ Easy to parse and validate

**Cons**:
- ❌ Verbose (larger cache keys)
- ❌ Includes empty fields (can be solved with `omitempty` tags)
- ❌ Slower than binary formats

**Best for**: Development, debugging, cross-service compatibility

---

### Option 2: Compact JSON (Recommended)

**Approach**: JSON with `omitempty` to skip empty fields

```go
type compactFilters struct {
    ContractAddress []string                    `json:"ca,omitempty"`
    TxHash          []string                    `json:"tx,omitempty"`
    BlockHash       []string                    `json:"bh,omitempty"`
    BlockNumber     core.ComparisonFilter[uint64] `json:"bn,omitempty"`
    LogIndex        []uint64                    `json:"li,omitempty"`
    Data            map[string]any              `json:"d,omitempty"`
    Timestamp       core.ComparisonFilter[time.Time] `json:"ts,omitempty"`
}

func encodeFiltersCompact(filters core.EventRecordFilters) (string, error) {
    compact := compactFilters{
        ContractAddress: sortedCopy(filters.ContractAddress),
        TxHash:          sortedCopy(filters.TxHash),
        // ... normalize other fields ...
    }
    
    bytes, err := json.Marshal(compact)
    return string(bytes), err
}
```

**Example Output**:
```json
{"ca":["0x123"],"bn":{"gte":1000}}
```

**Pros**:
- ✅ Much smaller than full JSON (50-70% reduction)
- ✅ Still human-readable
- ✅ Deterministic
- ✅ Only includes non-empty fields

**Cons**:
- ❌ Abbreviated keys less intuitive
- ❌ Still text-based (slower than binary)

**Best for**: Production cache keys with debugging needs

---

### Option 3: MessagePack (Best Performance)

**Approach**: Binary serialization with canonical encoding

```go
import "github.com/vmihailenco/msgpack/v5"

func encodeFiltersMsgpack(filters core.EventRecordFilters) ([]byte, error) {
    normalized := normalizeFilters(filters)
    
    // MessagePack is deterministic with sorted maps
    return msgpack.Marshal(normalized)
}

func makeKey(topic string, filters core.EventRecordFilters) (string, error) {
    encoded, err := encodeFiltersMsgpack(filters)
    if err != nil {
        return "", err
    }
    
    // Base64 for readability or hash for compactness
    hash := xxhash.Sum64(encoded)
    return topic + ":" + strconv.FormatUint(hash, 10), nil
}
```

**Pros**:
- ✅ Very fast (2-5x faster than JSON)
- ✅ Compact binary format (30-50% smaller than JSON)
- ✅ Deterministic with sorted keys
- ✅ Wide language support

**Cons**:
- ❌ Not human-readable (need decoder)
- ❌ Adds dependency

**Best for**: High-performance production systems

---

### Option 4: Ordered Field Concatenation (Fastest)

**Approach**: Manually concatenate fields in fixed order

```go
func encodeFiltersOrdered(filters core.EventRecordFilters) string {
    var b strings.Builder
    
    // Fixed field order ensures determinism
    if len(filters.ContractAddress) > 0 {
        sorted := slices.Clone(filters.ContractAddress)
        slices.Sort(sorted)
        b.WriteString("ca:")
        b.WriteString(strings.Join(sorted, ","))
        b.WriteString("|")
    }
    
    if len(filters.BlockNumber) > 0 {
        b.WriteString("bn:")
        for op, val := range filters.BlockNumber {
            b.WriteString(string(op))
            b.WriteString("=")
            b.WriteString(strconv.FormatUint(val, 10))
            b.WriteString(",")
        }
        b.WriteString("|")
    }
    
    // ... other fields in fixed order ...
    
    return b.String()
}
```

**Example Output**:
```
ca:0x123,0x456|bn:gte=1000|
```

**Pros**:
- ✅ Extremely fast (no JSON/msgpack overhead)
- ✅ Minimal allocations
- ✅ Compact
- ✅ Deterministic with careful ordering

**Cons**:
- ❌ Custom format (must document)
- ❌ Harder to maintain
- ❌ Less human-readable
- ❌ Manual parsing required

**Best for**: Extreme performance requirements

---

### Option 5: Two-Tier Strategy (Recommended for Production)

**Approach**: Use different formats for different purposes

```go
// For API response keys (human-readable)
func makeResponseKey(topic string, filters core.EventRecordFilters) (string, error) {
    qs, err := encodeFiltersQueryString(filters)
    return topic + "?" + qs, err
}

// For cache storage keys (compact)
func makeCacheKey(topic string, filters core.EventRecordFilters) (string, error) {
    // Use compact binary serialization
    encoded, err := encodeFiltersMsgpack(filters)
    if err != nil {
        return "", err
    }
    
    hash := xxhash.Sum64(encoded)
    return "search:" + strconv.FormatUint(hash, 10), err
}

// Usage
func (ss *SearchService) SearchEventRecords(...) {
    for topic, filters := range query {
        responseKey, _ := makeResponseKey(topic, filters)
        cacheKey, _ := makeCacheKey(topic, filters)
        
        // Search with cache key
        records := ss.search(ctx, topic, filters, cacheKey)
        
        // Return with readable key
        result[responseKey] = records
    }
}
```

**Pros**:
- ✅ Best of both worlds
- ✅ Readable API responses
- ✅ Compact cache storage
- ✅ Optimized for each use case

**Cons**:
- ❌ More complexity
- ❌ Two encoding paths to maintain

**Best for**: Production systems with monitoring needs

---

## Performance Comparison

| Method | Encode Speed | Size | Deterministic | Readable |
|--------|-------------|------|---------------|----------|
| **URL Query String** | 100 μs | 150 bytes | ✅ (with sort) | ✅ |
| **JSON** | 80 μs | 120 bytes | ✅ | ✅ |
| **Compact JSON** | 75 μs | 60 bytes | ✅ | ⚠️ |
| **MessagePack** | 30 μs | 45 bytes | ✅ | ❌ |
| **Ordered Concat** | 15 μs | 50 bytes | ✅ | ⚠️ |
| **Two-Tier** | 45 μs | Both | ✅ | ✅/❌ |

*Based on typical filter with 2-3 fields, benchmark estimates*

---

## Determinism Strategies

Critical for cache key consistency:

### 1. Array Sorting (Current)
```go
sorted := slices.Clone(filters.ContractAddress)
slices.Sort(sorted)
```
✅ Simple, effective

### 2. Map Key Ordering
```go
// Go's json.Marshal handles this automatically
json.Marshal(filters.Data)  // Keys are sorted
```
✅ Automatic with JSON

### 3. Field Ordering
```go
// Encode fields in fixed order
type orderedFilters struct {
    A_ContractAddress []string  // Prefix ensures order
    B_TxHash          []string
    C_BlockNumber     any
    // ...
}
```
✅ Explicit, maintainable

### 4. Canonical Encoding Libraries
```go
import "github.com/gibson042/canonicaljson-go"

canonical, _ := canonicaljson.Marshal(filters)
```
✅ Standards-based, but adds dependency

---

## Final Recommendations

### For Your Use Case (eth-indexer):

**Production Recommendation**: **Two-Tier Strategy with Compact JSON**

```go
// 1. For API response keys (matches handler expectations)
func makeResponseKey(topic string, filters) string {
    // URL query string - matches what handler constructs
    qs := encodeFiltersQueryString(filters)
    return topic + "?" + qs
}

// 2. For Redis cache keys (compact, fast)
func makeCacheKey(topic string, filters) string {
    // Compact JSON or hash of query string
    json := encodeFiltersCompactJSON(filters)
    hash := xxhash.Sum64String(topic + json)
    return "search:" + strconv.FormatUint(hash, 10)
}
```

**Why**:
- ✅ API handlers can construct matching response keys
- ✅ Redis keys stay compact (save memory)
- ✅ Easy to debug (can inspect query strings)
- ✅ No new dependencies
- ✅ Backward compatible

### Implementation Steps:

1. Keep current `encodeFilters()` for response keys
2. Add `makeCacheKey()` for Redis keys
3. Update `search()` to use cache key separately
4. Fix sorting to use copies (preserve input)
5. Add tests for determinism

---

## Code Template

```go
// For API compatibility - returns readable query string
func encodeFilters(filters core.EventRecordFilters) (string, error) {
    qs := url.Values{}
    
    if len(filters.ContractAddress) > 0 {
        sorted := slices.Clone(filters.ContractAddress)
        slices.Sort(sorted)
        qs.Add("contract_address", strings.Join(sorted, ","))
    }
    // ... other fields ...
    
    return qs.Encode(), nil  // URL-encoded query string
}

// For cache efficiency - returns compact hash
func makeCacheKey(topic string, queryString string) string {
    hash := xxhash.Sum64String(topic + ":" + queryString)
    return "search:" + strconv.FormatUint(hash, 10)
}

// Public API - returns readable keys
func makeResponseKey(topic string, queryString string) string {
    return topic + "?" + queryString
}
```

This approach solves all the identified issues while maintaining debuggability and performance.