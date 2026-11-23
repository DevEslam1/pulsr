package hub

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

var testUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func TestHub_AttachDetachDrop(t *testing.T) {
	h := NewHub()

	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := testUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		sc := h.Attach("ROOM1", "user1", conn)
		defer func() {
			h.Detach("ROOM1", "user1", sc)
			_ = sc.Close()
		}()

		// Read one message to keep open
		_, _, _ = conn.ReadMessage()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial failed: %v", err)
	}
	defer conn.Close()

	// Wait briefly for attachment
	time.Sleep(50 * time.Millisecond)

	online := h.MembersOnline("ROOM1")
	if len(online) != 1 || online[0] != "user1" {
		t.Fatalf("Expected [user1], got %v", online)
	}

	codes := h.ActiveCodes()
	if len(codes) != 1 || codes[0] != "ROOM1" {
		t.Fatalf("Expected [ROOM1], got %v", codes)
	}

	// Test broadcast
	h.Broadcast("ROOM1", map[string]string{"msg": "hello"}, "")

	var resp map[string]string
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := conn.ReadJSON(&resp); err != nil {
		t.Fatalf("Failed to read broadcast message: %v", err)
	}
	if resp["msg"] != "hello" {
		t.Fatalf("Expected 'hello', got %s", resp["msg"])
	}

	// Test DropParty
	h.DropParty("ROOM1")
	if len(h.MembersOnline("ROOM1")) != 0 {
		t.Fatalf("Expected 0 members after DropParty")
	}
}

func TestHub_CloseAll(t *testing.T) {
	h := NewHub()

	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := testUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		_ = h.Attach("ROOM2", "user2", conn)
		_, _, _ = conn.ReadMessage()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial failed: %v", err)
	}
	defer conn.Close()

	time.Sleep(50 * time.Millisecond)
	h.CloseAll()

	if len(h.ActiveCodes()) != 0 {
		t.Fatalf("Expected 0 active codes after CloseAll, got %v", h.ActiveCodes())
	}
}

func TestSafeConn_ClosesOnSendOverflowAndCloseWithJSONNonBlocking(t *testing.T) {
	h := NewHub()
	attached := make(chan *SafeConn, 1)
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := testUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		sc := h.Attach("OVERFLOW", "u1", conn)
		attached <- sc
		defer func() {
			h.Detach("OVERFLOW", "u1", sc)
			_ = sc.Close()
		}()
		_, _, _ = conn.ReadMessage()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")
	clientConn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial failed: %v", err)
	}
	defer clientConn.Close()

	sc := <-attached

	// Simulate a stalled writePump holding s.mu: send one frame first so
	// writePump pulls it from sendQueue and blocks waiting on s.mu, then fill
	// all queueSize slots in sendQueue.
	sc.mu.Lock()
	if err := sc.WriteJSON(map[string]int{"in_flight": 1}); err != nil {
		sc.mu.Unlock()
		t.Fatalf("expected in-flight frame to enqueue, got %v", err)
	}
	time.Sleep(20 * time.Millisecond)
	for i := 0; i < queueSize; i++ {
		if err := sc.WriteJSON(map[string]int{"i": i}); err != nil {
			sc.mu.Unlock()
			t.Fatalf("expected item %d to enqueue, got %v", i, err)
		}
	}

	// The next write overflows the queue and must close SafeConn non-blockingly
	// without waiting for s.mu.
	done := make(chan error, 1)
	go func() {
		done <- sc.WriteJSON(map[string]int{"overflow": 1})
	}()
	select {
	case err := <-done:
		if err == nil {
			sc.mu.Unlock()
			t.Fatalf("expected overflow error")
		}
	case <-time.After(500 * time.Millisecond):
		sc.mu.Unlock()
		t.Fatalf("WriteJSON blocked on s.mu during overflow close")
	}
	sc.mu.Unlock()

	// Subsequent WriteJSON must fail because SafeConn is closed.
	if err := sc.WriteJSON(map[string]string{"after": "close"}); err == nil {
		t.Fatalf("expected WriteJSON on closed SafeConn to fail")
	}

	// Client must observe socket close.
	_ = clientConn.SetReadDeadline(time.Now().Add(time.Second))
	if _, _, err := clientConn.ReadMessage(); err == nil {
		t.Fatalf("expected client read to fail after overflow close")
	}
}

func TestSafeConn_CloseWithJSONDoesNotBlockOnMutex(t *testing.T) {
	h := NewHub()
	attached := make(chan *SafeConn, 1)
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := testUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		sc := h.Attach("NONBLOCK", "u1", conn)
		attached <- sc
		defer func() {
			h.Detach("NONBLOCK", "u1", sc)
			_ = sc.Close()
		}()
		_, _, _ = conn.ReadMessage()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")
	clientConn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("Dial failed: %v", err)
	}
	defer clientConn.Close()

	sc := <-attached
	sc.mu.Lock()

	returned := make(chan struct{})
	go func() {
		_ = sc.CloseWithJSON(map[string]string{"type": "bye", "reason": "expired"})
		close(returned)
	}()

	select {
	case <-returned:
	case <-time.After(300 * time.Millisecond):
		sc.mu.Unlock()
		t.Fatalf("CloseWithJSON blocked waiting on s.mu")
	}
	sc.mu.Unlock()

	var bye map[string]string
	_ = clientConn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := clientConn.ReadJSON(&bye); err != nil {
		t.Fatalf("expected bye frame after mutex release, got %v", err)
	}
	if bye["type"] != "bye" || bye["reason"] != "expired" {
		t.Fatalf("unexpected bye frame: %+v", bye)
	}
}

func TestHub_DropPartyWithBye(t *testing.T) {
	h := NewHub()
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := testUpgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		member := r.URL.Query().Get("m")
		sc := h.Attach("EXP1", member, conn)
		defer func() {
			h.Detach("EXP1", member, sc)
			_ = sc.Close()
		}()
		_, _, _ = conn.ReadMessage()
	}))
	defer s.Close()

	wsURL := "ws" + strings.TrimPrefix(s.URL, "http")
	c1, _, err := websocket.DefaultDialer.Dial(wsURL+"?m=u1", nil)
	if err != nil {
		t.Fatalf("dial 1 failed: %v", err)
	}
	defer c1.Close()
	c2, _, err := websocket.DefaultDialer.Dial(wsURL+"?m=u2", nil)
	if err != nil {
		t.Fatalf("dial 2 failed: %v", err)
	}
	defer c2.Close()

	time.Sleep(50 * time.Millisecond)
	h.DropPartyWithBye("EXP1", map[string]interface{}{"type": "bye", "reason": "expired"})

	if len(h.ActiveCodes()) != 0 {
		t.Fatalf("expected 0 active codes after DropPartyWithBye, got %v", h.ActiveCodes())
	}

	for idx, c := range []*websocket.Conn{c1, c2} {
		var msg map[string]interface{}
		_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
		if err := c.ReadJSON(&msg); err != nil {
			t.Fatalf("client %d failed to read bye: %v", idx+1, err)
		}
		if msg["type"] != "bye" || msg["reason"] != "expired" {
			t.Fatalf("client %d got unexpected frame: %+v", idx+1, msg)
		}
	}
}
