package core

type State map[string]uint64

type StateStorage interface {
	Get() (State, error)
	Set(State) error
}
