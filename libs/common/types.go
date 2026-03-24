package common

type ComparisonOp string

const (
	LT  ComparisonOp = "lt"
	LTE ComparisonOp = "lte"
	GT  ComparisonOp = "gt"
	GTE ComparisonOp = "gte"
	EQ  ComparisonOp = "eq"
)

type ComparisonFilter[T any] map[ComparisonOp]T

type PagingOptions[CursorT any] struct {
	Cursor *CursorT
	Limit  uint64
}
