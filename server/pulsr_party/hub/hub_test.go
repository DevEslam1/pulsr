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
