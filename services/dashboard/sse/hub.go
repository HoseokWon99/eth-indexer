package sse

import (
	"log"
	"sync"
)

// Hub manages SSE client registration and broadcast.
type Hub struct {
	mu      sync.RWMutex
	clients map[chan []byte]struct{}

	register   chan chan []byte
	unregister chan chan []byte
	broadcast  chan []byte
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[chan []byte]struct{}),
		register:   make(chan chan []byte, 16),
		unregister: make(chan chan []byte, 16),
		broadcast:  make(chan []byte, 256),
	}
}

func (h *Hub) Register(ch chan []byte) {
	h.register <- ch
}

func (h *Hub) Unregister(ch chan []byte) {
	h.unregister <- ch
}

func (h *Hub) Broadcast(data []byte) {
	h.broadcast <- data
}

// Run processes register/unregister/broadcast events. Call in a goroutine.
func (h *Hub) Run() {
	for {
		select {
		case ch := <-h.register:
			h.mu.Lock()
			h.clients[ch] = struct{}{}
			h.mu.Unlock()

		case ch := <-h.unregister:
			h.mu.Lock()
			delete(h.clients, ch)
			h.mu.Unlock()
			close(ch)

		case data := <-h.broadcast:
			h.mu.RLock()
			for ch := range h.clients {
				select {
				case ch <- data:
				default:
					log.Printf("sse: client buffer full — dropping message")
				}
			}
			h.mu.RUnlock()
		}
	}
}
