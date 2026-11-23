package hub

import (
	"errors"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait = 5 * time.Second
	queueSize = 64
)

// SafeConn wraps *websocket.Conn with a bounded send queue and mutex to prevent concurrent writes
// and avoid unconstrained goroutine creation on broadcasts.
type SafeConn struct {
	mu            sync.Mutex
	conn          *websocket.Conn
	sendQueue     chan interface{}
	done          chan struct{}
	closeOnce     sync.Once
	closeConnOnce sync.Once
}

func NewSafeConn(conn *websocket.Conn) *SafeConn {
	sc := &SafeConn{
		conn:      conn,
		sendQueue: make(chan interface{}, queueSize),
		done:      make(chan struct{}),
	}
	go sc.writePump()
	return sc
}

func (s *SafeConn) closeUnderlying() error {
	var err error
	s.closeConnOnce.Do(func() {
		err = s.conn.Close()
	})
	return err
}

func (s *SafeConn) writePump() {
	for {
		select {
		case <-s.done:
			return
		default:
		}
		select {
		case msg, ok := <-s.sendQueue:
			if !ok {
				return
			}
			s.mu.Lock()
			select {
			case <-s.done:
				s.mu.Unlock()
				return
			default:
			}
			_ = s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			err := s.conn.WriteJSON(msg)
			s.mu.Unlock()
			if err != nil {
				_ = s.Close()
				return
			}
		case <-s.done:
			return
		}
	}
}

func (s *SafeConn) WriteJSON(v interface{}) error {
	select {
	case <-s.done:
		return errors.New("connection closed")
	default:
	}

	select {
	case s.sendQueue <- v:
		return nil
	default:
		// Close slow connections on overflow rather than silently dropping frames
		// and leaving the client permanently desynchronized.
		_ = s.Close()
		return errors.New("send queue full")
	}
}

func (s *SafeConn) Close() error {
	return s.CloseWithJSON(nil)
}

func (s *SafeConn) CloseWithJSON(v interface{}) error {
	var err error
	s.closeOnce.Do(func() {
		close(s.done)
		if v == nil {
			// Close the underlying net.Conn directly without taking s.mu so a
			// stalled writePump immediately aborts instead of blocking callers.
			err = s.closeUnderlying()
			return
		}
		// Flush the final payload without blocking callers on s.mu if writePump is
		// stuck on a slow socket; bound the wait by writeWait.
		go func() {
			timer := time.AfterFunc(writeWait, func() {
				_ = s.closeUnderlying()
			})
			s.mu.Lock()
			timer.Stop()
			_ = s.conn.SetWriteDeadline(time.Now().Add(writeWait))
			_ = s.conn.WriteJSON(v)
			_ = s.closeUnderlying()
			s.mu.Unlock()
		}()
	})
	return err
}

// Hub coordinates active WebSocket connections across rooms with O(1) room lookups.
type Hub struct {
	mu      sync.RWMutex
	sockets map[string]map[string]*SafeConn // code -> memberId -> SafeConn
}

func NewHub() *Hub {
	return &Hub{
		sockets: make(map[string]map[string]*SafeConn),
	}
}

func (h *Hub) Attach(code, memberId string, conn *websocket.Conn) *SafeConn {
	sc := NewSafeConn(conn)
	h.mu.Lock()
	room, ok := h.sockets[code]
	if !ok {
		room = make(map[string]*SafeConn)
		h.sockets[code] = room
	}
	prev := room[memberId]
	room[memberId] = sc
	h.mu.Unlock()

	// Close previous connection outside lock so it doesn't stall other parties
	if prev != nil && prev != sc {
		_ = prev.Close()
	}
	return sc
}

func (h *Hub) Detach(code, memberId string, sc *SafeConn) bool {
	h.mu.Lock()
	defer h.mu.Unlock()

	room, ok := h.sockets[code]
	if !ok {
		return false
	}
	detached := false
	if room[memberId] == sc {
		delete(room, memberId)
		detached = true
	}
	if len(room) == 0 {
		delete(h.sockets, code)
	}
	return detached
}

func (h *Hub) DropParty(code string) {
	h.DropPartyWithBye(code, nil)
}

// DropPartyWithBye removes code from the hub and closes every socket in the
// room, optionally flushing a final bye frame before closing.
func (h *Hub) DropPartyWithBye(code string, byePayload interface{}) {
	h.mu.Lock()
	room := h.sockets[code]
	delete(h.sockets, code)
	h.mu.Unlock()

	for _, sc := range room {
		_ = sc.CloseWithJSON(byePayload)
	}
}

func (h *Hub) CloseAll() {
	h.mu.Lock()
	rooms := h.sockets
	h.sockets = make(map[string]map[string]*SafeConn)
	h.mu.Unlock()

	for _, room := range rooms {
		for _, sc := range room {
			_ = sc.Close()
		}
	}
}

func (h *Hub) MembersOnline(code string) []string {
	h.mu.RLock()
	defer h.mu.RUnlock()

	room := h.sockets[code]
	if room == nil {
		return nil
	}
	members := make([]string, 0, len(room))
	for mid := range room {
		members = append(members, mid)
	}
	return members
}

func (h *Hub) ActiveCodes() []string {
	h.mu.RLock()
	defer h.mu.RUnlock()

	codes := make([]string, 0, len(h.sockets))
	for c := range h.sockets {
		codes = append(codes, c)
	}
	return codes
}

func (h *Hub) Send(code, memberId string, payload interface{}) {
	h.mu.RLock()
	room := h.sockets[code]
	var target *SafeConn
	if room != nil {
		target = room[memberId]
	}
	h.mu.RUnlock()

	if target != nil {
		_ = target.WriteJSON(payload)
	}
}

func (h *Hub) CloseMember(code, memberId string) {
	h.CloseMemberWithBye(code, memberId, nil)
}

func (h *Hub) CloseMemberWithBye(code, memberId string, byePayload interface{}) {
	h.mu.RLock()
	room := h.sockets[code]
	var target *SafeConn
	if room != nil {
		target = room[memberId]
	}
	h.mu.RUnlock()
	if target != nil {
		_ = target.CloseWithJSON(byePayload)
	}
}

func (h *Hub) Broadcast(code string, payload interface{}, skipMemberId string) {
	h.mu.RLock()
	room := h.sockets[code]
	if room == nil || len(room) == 0 {
		h.mu.RUnlock()
		return
	}
	targets := make([]*SafeConn, 0, len(room))
	for mid, sc := range room {
		if mid != skipMemberId {
			targets = append(targets, sc)
		}
	}
	h.mu.RUnlock()

	// Enqueue to targets' bounded channels non-blockingly without unbounded goroutine spawning
	for _, sc := range targets {
		_ = sc.WriteJSON(payload)
	}
}
