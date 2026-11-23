package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/pulsr-audio/pulsr/server/party/clock"
	"github.com/pulsr-audio/pulsr/server/party/config"
	"github.com/pulsr-audio/pulsr/server/party/hub"
	"github.com/pulsr-audio/pulsr/server/party/party"
	"github.com/pulsr-audio/pulsr/server/party/presence"
	"github.com/pulsr-audio/pulsr/server/party/protocol"
)

func setupTestServer() *httptest.Server {
	store = party.NewPartyStore()
	hubInst = hub.NewHub()
	createLimiter = newIPRateLimiter(time.Minute, 100, 100)
	joinLimiter = newIPRateLimiter(time.Minute, 100, 100)
	readLimiter = newIPRateLimiter(time.Minute, 100, 100)
	presenceLimiter = newIPRateLimiter(time.Minute, 100, 100)
	return httptest.NewServer(corsMiddleware(buildMux()))
}

func TestRESTEndpoints(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// 1. Health check
	res, err := http.Get(ts.URL + "/healthz")
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("GET /healthz failed: status %v, err %v", res.StatusCode, err)
	}
	var health map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&health)
	if health["ok"] != true {
		t.Fatalf("Expected ok: true in healthz")
	}

	// 1b. Non-existent subpaths must return 404, not root 200
	resBogusHealth, err := http.Get(ts.URL + "/1324/healthz")
	if err != nil || resBogusHealth.StatusCode != http.StatusNotFound {
		t.Fatalf("Expected 404 for /1324/healthz, got %v, err %v", resBogusHealth.StatusCode, err)
	}
	resBogusPath, err := http.Get(ts.URL + "/1324")
	if err != nil || resBogusPath.StatusCode != http.StatusNotFound {
		t.Fatalf("Expected 404 for /1324, got %v, err %v", resBogusPath.StatusCode, err)
	}

	// 2. Server time
	resTime, err := http.Get(ts.URL + "/api/time")
	if err != nil || resTime.StatusCode != http.StatusOK {
		t.Fatalf("GET /api/time failed: status %v, err %v", resTime.StatusCode, err)
	}
	var timeResp map[string]interface{}
	_ = json.NewDecoder(resTime.Body).Decode(&timeResp)
	if _, ok := timeResp["serverMs"].(float64); !ok {
		t.Fatalf("Expected numeric serverMs")
	}

	// 3. Create Party
	createBody := map[string]string{
		"userId":      "u_alice",
		"deviceId":    "d_alice",
		"displayName": "Alice",
	}
	b, _ := json.Marshal(createBody)
	createRes, err := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(b))
	if err != nil || createRes.StatusCode != http.StatusCreated {
		t.Fatalf("POST /api/parties failed: status %v, err %v", createRes.StatusCode, err)
	}
	var partyResp map[string]interface{}
	_ = json.NewDecoder(createRes.Body).Decode(&partyResp)

	code, _ := partyResp["code"].(string)
	token, _ := partyResp["token"].(string)
	if code == "" || token == "" {
		t.Fatalf("Expected code and token in response")
	}

	// 4. Join Party
	joinBody := map[string]string{
		"userId":      "u_bob",
		"deviceId":    "d_bob",
		"displayName": "Bob",
	}
	jb, _ := json.Marshal(joinBody)
	joinRes, err := http.Post(fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), "application/json", bytes.NewReader(jb))
	if err != nil || joinRes.StatusCode != http.StatusOK {
		t.Fatalf("POST /api/parties/%s/join failed: status %v", code, joinRes.StatusCode)
	}

	// 5. Get Party with token
	req, _ := http.NewRequest("GET", fmt.Sprintf("%s/api/parties/%s", ts.URL, code), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	getRes, err := http.DefaultClient.Do(req)
	if err != nil || getRes.StatusCode != http.StatusOK {
		t.Fatalf("GET /api/parties/%s failed with token: status %v", code, getRes.StatusCode)
	}

	// 6. Get Party without token should be 401
	unauthReq, _ := http.NewRequest("GET", fmt.Sprintf("%s/api/parties/%s", ts.URL, code), nil)
	unauthRes, err := http.DefaultClient.Do(unauthReq)
	if err != nil || unauthRes.StatusCode != http.StatusUnauthorized {
		t.Fatalf("Expected 401 Unauthorized, got %v", unauthRes.StatusCode)
	}
}

func TestWebSocketFlow(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// Create Party
	createBody := map[string]string{
		"userId":      "u1",
		"deviceId":    "d1",
		"displayName": "Host",
	}
	b, _ := json.Marshal(createBody)
	res, _ := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(b))
	var pResp map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&pResp)
	code := pResp["code"].(string)
	token := pResp["token"].(string)

	// Connect WebSocket
	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = fmt.Sprintf("/ws/parties/%s", code)
	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)
	ws, _, err := websocket.DefaultDialer.Dial(u.String(), headers)
	if err != nil {
		t.Fatalf("WebSocket connection failed: %v", err)
	}
	defer ws.Close()

	// 1. Should receive welcome frame
	var welcome map[string]interface{}
	_ = ws.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := ws.ReadJSON(&welcome); err != nil {
		t.Fatalf("Failed to read welcome frame: %v", err)
	}
	if welcome["type"] != protocol.FrameWelcome {
		t.Fatalf("Expected welcome frame, got: %v", welcome["type"])
	}

	// 2. May receive members frame from broadcast
	_ = ws.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	var nextFrame map[string]interface{}
	if err := ws.ReadJSON(&nextFrame); err == nil {
		if nextFrame["type"] != protocol.FrameMembers && nextFrame["type"] != protocol.FrameState {
			t.Logf("Received broadcast frame: %v", nextFrame["type"])
		}
	}

	// 3. Send Ping, expect Pong
	ping := map[string]interface{}{
		"type":     protocol.FramePing,
		"clientMs": 123456789,
	}
	if err := ws.WriteJSON(ping); err != nil {
		t.Fatalf("Failed to write ping: %v", err)
	}

	var pong map[string]interface{}
	for {
		_ = ws.SetReadDeadline(time.Now().Add(2 * time.Second))
		if err := ws.ReadJSON(&pong); err != nil {
			t.Fatalf("Failed to read pong: %v", err)
		}
		if pong["type"] == protocol.FramePong {
			break
		}
	}
	if pong["clientMs"] != float64(123456789) {
		t.Errorf("Expected pong clientMs to match, got %v", pong["clientMs"])
	}

	// 4. Send queueAdd control
	addControl := map[string]interface{}{
		"type":   protocol.FrameControl,
		"action": protocol.ActionQueueAdd,
		"track": map[string]interface{}{
			"videoId": "abc_song",
			"title":   "Test Song",
			"artist":  "Artist",
		},
	}
	if err := ws.WriteJSON(addControl); err != nil {
		t.Fatalf("Failed to send queueAdd: %v", err)
	}

	// Read until queue frame or state frame received
	var receivedQueue bool
	for i := 0; i < 5; i++ {
		_ = ws.SetReadDeadline(time.Now().Add(2 * time.Second))
		var f map[string]interface{}
		if err := ws.ReadJSON(&f); err != nil {
			break
		}
		if f["type"] == protocol.FrameQueue {
			receivedQueue = true
			qData, _ := f["queue"].(map[string]interface{})
			items, _ := qData["items"].([]interface{})
			if len(items) != 1 {
				t.Errorf("Expected 1 item in queue, got %d", len(items))
			}
			break
		}
	}
	if !receivedQueue {
		t.Fatalf("Expected queue broadcast after queueAdd")
	}
}

func TestCreateRateLimiter(t *testing.T) {
	limiter := newIPRateLimiter(time.Minute, 2, 100)
	if !limiter.Allow("203.0.113.10") || !limiter.Allow("203.0.113.10") {
		t.Fatal("expected the first two creations from an IP to be allowed")
	}
	if limiter.Allow("203.0.113.10") {
		t.Fatal("expected the third creation from an IP to be rate limited")
	}
	if !limiter.Allow("203.0.113.11") {
		t.Fatal("expected a separate IP to have its own allowance")
	}
}

func TestRateLimiterFreesExpiredEntriesWhenFull(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newIPRateLimiter(time.Minute, 5, 1)
	limiter.nowFn = func() time.Time { return now }

	if !limiter.Allow("203.0.113.20") {
		t.Fatal("expected the first IP to fit")
	}
	// Age past window; sweep removes expired entry cleanly before inserting new IP.
	now = now.Add(2 * time.Minute)
	if !limiter.Allow("203.0.113.21") {
		t.Fatal("expected the expired entry to be swept for the new IP")
	}
	if _, exists := limiter.entries["203.0.113.20"]; exists {
		t.Fatal("expected expired IP to be deleted from table")
	}
}

func TestRateLimiterLRUEvictionPreventsGlobalDoS(t *testing.T) {
	now := time.Unix(2000, 0)
	limiter := newIPRateLimiter(time.Minute, 2, 2)
	limiter.nowFn = func() time.Time { return now }

	// Fill table to capacity=2: [203.0.113.2, 203.0.113.1] (most-recent -> least-recent)
	if !limiter.Allow("203.0.113.1") || !limiter.Allow("203.0.113.2") {
		t.Fatal("expected initial entries to be allowed")
	}
	// Touch .1 again so .2 becomes least recently used and .1 reaches its limit of 2.
	if !limiter.Allow("203.0.113.1") {
		t.Fatal("expected second hit from .1 to be allowed")
	}

	// Attacker floods with new IPs: table must evict LRU (.2) rather than
	// globally denying all new legitimate IPs.
	if !limiter.Allow("203.0.113.3") {
		t.Fatal("expected new legitimate IP to succeed via LRU eviction, not global DoS")
	}
	if len(limiter.entries) > 2 {
		t.Fatalf("expected bounded entries <= 2, got %d", len(limiter.entries))
	}
	if _, ok := limiter.entries["203.0.113.2"]; ok {
		t.Fatal("expected least-recently-used IP 203.0.113.2 to be evicted")
	}
	// Recently active IP (.1) was retained and remains rate limited on its 3rd hit.
	if limiter.Allow("203.0.113.1") {
		t.Fatal("expected recently active IP 203.0.113.1 to remain tracked and rate limited")
	}
}

func TestClientIPRightToLeftAndTrustedProxies(t *testing.T) {
	oldTrust := config.TrustProxy
	oldHops := config.TrustedProxyHops
	oldProxies := config.TrustedProxies
	oldHeader := config.ClientIPHeader
	defer func() {
		config.TrustProxy = oldTrust
		config.TrustedProxyHops = oldHops
		config.TrustedProxies = oldProxies
		config.ClientIPHeader = oldHeader
	}()

	// 1. TrustProxy=false must ignore X-Forwarded-For and edge headers.
	config.TrustProxy = false
	config.TrustedProxyHops = 1
	config.TrustedProxies = nil
	config.ClientIPHeader = "True-Client-IP"
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "198.51.100.10:54321"
	r.Header.Set("X-Forwarded-For", "1.2.3.4")
	r.Header.Set("True-Client-IP", "5.6.7.8")
	if got := clientIP(r); got != "198.51.100.10" {
		t.Fatalf("TrustProxy=false returned %q, want 198.51.100.10", got)
	}

	// 2. TrustProxy=true, 1 proxy hop: rightmost entry wins over spoofed leftmost entries.
	config.TrustProxy = true
	config.TrustedProxyHops = 1
	config.ClientIPHeader = ""
	r = httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "127.0.0.1:4444"
	r.Header.Add("X-Forwarded-For", "10.99.99.99, 192.0.2.50")
	r.Header.Add("X-Forwarded-For", "203.0.113.9")
	if got := clientIP(r); got != "203.0.113.9" {
		t.Fatalf("1-hop XFF returned %q, want 203.0.113.9", got)
	}

	// 3. TrustProxy=true, 2 proxy hops: skip 1 proxy hop inside XFF from the right.
	config.TrustedProxyHops = 2
	r = httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "127.0.0.1:4444"
	r.Header.Set("X-Forwarded-For", "1.2.3.4, 203.0.113.42, 172.64.0.1")
	if got := clientIP(r); got != "203.0.113.42" {
		t.Fatalf("2-hop XFF returned %q, want 203.0.113.42", got)
	}

	// 4. Configured TrustedProxies CIDR check: untrusted peer cannot spoof XFF.
	config.TrustedProxyHops = 1
	config.TrustedProxies = config.ParseTrustedProxies([]string{"127.0.0.1/8", "10.0.0.0/8"})
	rUntrusted := httptest.NewRequest("GET", "/", nil)
	rUntrusted.RemoteAddr = "198.51.100.88:9000"
	rUntrusted.Header.Set("X-Forwarded-For", "1.2.3.4")
	if got := clientIP(rUntrusted); got != "198.51.100.88" {
		t.Fatalf("untrusted peer returned %q, want 198.51.100.88", got)
	}

	// Trusted peer skips right-to-left only across trusted proxy hops.
	rTrusted := httptest.NewRequest("GET", "/", nil)
	rTrusted.RemoteAddr = "127.0.0.1:9000"
	rTrusted.Header.Set("X-Forwarded-For", "9.9.9.9, 203.0.113.77, 10.1.2.3")
	if got := clientIP(rTrusted); got != "203.0.113.77" {
		t.Fatalf("trusted proxy chain returned %q, want 203.0.113.77", got)
	}

	// 5. Configured platform edge header wins when peer is trusted and header is valid IP.
	config.ClientIPHeader = "True-Client-IP"
	rEdge := httptest.NewRequest("GET", "/", nil)
	rEdge.RemoteAddr = "127.0.0.1:9000"
	rEdge.Header.Set("True-Client-IP", "203.0.113.120")
	rEdge.Header.Set("X-Forwarded-For", "1.2.3.4")
	if got := clientIP(rEdge); got != "203.0.113.120" {
		t.Fatalf("edge header returned %q, want 203.0.113.120", got)
	}

	// 6. Malformed XFF garbage falls back to RemoteAddr rather than poisoning limiter map.
	config.ClientIPHeader = ""
	config.TrustedProxies = nil
	rBad := httptest.NewRequest("GET", "/", nil)
	rBad.RemoteAddr = "127.0.0.1:9000"
	rBad.Header.Set("X-Forwarded-For", "not-an-ip-key")
	if got := clientIP(rBad); got != "127.0.0.1" {
		t.Fatalf("malformed XFF returned %q, want 127.0.0.1", got)
	}
}

func TestSpoofedXFFCannotExhaustRateLimiter(t *testing.T) {
	oldTrust := config.TrustProxy
	oldHops := config.TrustedProxyHops
	oldProxies := config.TrustedProxies
	oldHeader := config.ClientIPHeader
	defer func() {
		config.TrustProxy = oldTrust
		config.TrustedProxyHops = oldHops
		config.TrustedProxies = oldProxies
		config.ClientIPHeader = oldHeader
	}()

	config.TrustProxy = true
	config.TrustedProxyHops = 1
	config.TrustedProxies = nil
	config.ClientIPHeader = ""

	limiter := newIPRateLimiter(time.Minute, 2, 3)

	// Attacker rotates leftmost X-Forwarded-For values behind proxy, which appends
	// the attacker's actual IP on the right.
	for i := 0; i < 20; i++ {
		req := httptest.NewRequest("POST", "/api/parties", nil)
		req.RemoteAddr = "127.0.0.1:5000"
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("10.0.%d.%d, 198.51.100.77", i/250, i%250+1))
		allowed := limiter.Allow(clientIP(req))
		if i < 2 && !allowed {
			t.Fatalf("expected attacker's first 2 requests to pass")
		}
		if i >= 2 && allowed {
			t.Fatalf("expected attacker request %d to be rate limited despite spoofed XFF", i)
		}
	}

	// Legitimate user behind proxy must still be allowed.
	legitReq := httptest.NewRequest("POST", "/api/parties", nil)
	legitReq.RemoteAddr = "127.0.0.1:5001"
	legitReq.Header.Set("X-Forwarded-For", "203.0.113.55")
	if !limiter.Allow(clientIP(legitReq)) {
		t.Fatal("legitimate user was blocked after spoofed XFF flood")
	}
}

func postPresence(t *testing.T, ts *httptest.Server, body string, origin string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/presence", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /api/presence failed: %v", err)
	}
	return res
}

func liveStats(t *testing.T, ts *httptest.Server) presence.Counts {
	t.Helper()
	res, err := http.Get(ts.URL + "/api/stats/live")
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("GET /api/stats/live failed: status %v, err %v", res.StatusCode, err)
	}
	if got := res.Header.Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("stats must be readable from any site, got Access-Control-Allow-Origin %q", got)
	}
	var counts presence.Counts
	if err := json.NewDecoder(res.Body).Decode(&counts); err != nil {
		t.Fatalf("decode stats: %v", err)
	}
	return counts
}

func TestPresence(t *testing.T) {
	presenceTracker = presence.NewTracker(6*time.Minute, 1000)
	presenceLimiter = newIPRateLimiter(time.Minute, 100, 100)
	ts := setupTestServer()
	defer ts.Close()

	const phone = "3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b"
	const pc = "7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f"

	res := postPresence(t, ts, `{"id":"`+phone+`","platform":"android","open":true}`, "")
	if res.StatusCode != http.StatusOK {
		t.Fatalf("android ping: status %d", res.StatusCode)
	}
	var reply map[string]int
	_ = json.NewDecoder(res.Body).Decode(&reply)
	if reply["intervalSec"] != config.PresenceIntervalSec {
		t.Fatalf("expected intervalSec %d, got %v", config.PresenceIntervalSec, reply)
	}
	postPresence(t, ts, `{"id":"`+pc+`","platform":"pc","open":true}`, "")
	// The same install pinging again is still one install.
	postPresence(t, ts, `{"id":"`+phone+`","platform":"android","open":true}`, "")

	presenceTracker.Sweep(clock.NowMs())
	if got := liveStats(t, ts); got.Online != 2 || got.Android != 1 || got.PC != 1 {
		t.Fatalf("got %+v, want 2 online (1 android, 1 pc)", got)
	}

	postPresence(t, ts, `{"id":"`+pc+`","platform":"pc","open":false}`, "")
	presenceTracker.Sweep(clock.NowMs())
	if got := liveStats(t, ts); got.Online != 1 || got.PC != 0 {
		t.Fatalf("got %+v, want the closed pc gone", got)
	}

	rejected := []struct {
		name   string
		body   string
		origin string
		status int
	}{
		{"unknown platform", `{"id":"` + pc + `","platform":"ios","open":true}`, "", http.StatusUnprocessableEntity},
		{"desktop is not a platform name", `{"id":"` + pc + `","platform":"desktop","open":true}`, "", http.StatusUnprocessableEntity},
		{"bad id", `{"id":"abc","platform":"pc","open":true}`, "", http.StatusUnprocessableEntity},
		{"missing open", `{"id":"` + pc + `","platform":"pc"}`, "", http.StatusUnprocessableEntity},
		{"from a browser", `{"id":"` + pc + `","platform":"pc","open":true}`, "https://example.com", http.StatusForbidden},
	}
	for _, c := range rejected {
		if res := postPresence(t, ts, c.body, c.origin); res.StatusCode != c.status {
			t.Errorf("%s: status %d, want %d", c.name, res.StatusCode, c.status)
		}
	}
	presenceTracker.Sweep(clock.NowMs())
	if got := liveStats(t, ts); got.Online != 1 {
		t.Fatalf("rejected pings changed the count: %+v", got)
	}
}

func TestPresenceRateLimit(t *testing.T) {
	presenceTracker = presence.NewTracker(6*time.Minute, 1000)
	ts := setupTestServer()
	defer ts.Close()
	presenceLimiter = newIPRateLimiter(time.Minute, 2, 100)

	body := `{"id":"3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b","platform":"android","open":true}`
	postPresence(t, ts, body, "")
	postPresence(t, ts, body, "")
	if res := postPresence(t, ts, body, ""); res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("third ping in a minute: status %d, want 429", res.StatusCode)
	}
}

func TestLiveBadge(t *testing.T) {
	presenceTracker = presence.NewTracker(6*time.Minute, 1000)
	presenceLimiter = newIPRateLimiter(time.Minute, 100, 100)
	ts := setupTestServer()
	defer ts.Close()

	postPresence(t, ts, `{"id":"3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b","platform":"android","open":true}`, "")
	presenceTracker.Sweep(clock.NowMs())

	res, err := http.Get(ts.URL + "/api/stats/live/badge.svg")
	if err != nil || res.StatusCode != http.StatusOK {
		t.Fatalf("GET badge failed: status %v, err %v", res.StatusCode, err)
	}
	// GitHub's camo proxy only refetches when the origin says not to cache.
	if got := res.Header.Get("Cache-Control"); !strings.Contains(got, "no-cache") {
		t.Fatalf("badge must not be cached, got Cache-Control %q", got)
	}
	var body bytes.Buffer
	_, _ = body.ReadFrom(res.Body)
	// shields.io's own render of "LISTENING NOW: 1", so the badge looks unchanged.
	want := `<svg xmlns="http://www.w3.org/2000/svg" width="156.5" height="28" role="img" aria-label="LISTENING NOW: 1"><title>LISTENING NOW: 1</title><g shape-rendering="crispEdges"><rect width="124.25" height="28" fill="#0d1117"/><rect x="124.25" width="32.25" height="28" fill="#fb4f67"/></g><g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="100"><text transform="scale(.1)" x="621.25" y="175" textLength="1002.5">LISTENING NOW</text><text transform="scale(.1)" x="1403.75" y="175" textLength="82.5" font-weight="bold">1</text></g></svg>`
	if body.String() != want {
		t.Fatalf("badge svg differs from shields:\n got %s\nwant %s", body.String(), want)
	}
}

func TestRequestOrigin(t *testing.T) {
	r := httptest.NewRequest("GET", "http://example.com/invite/ABC123", nil)
	r.Header.Set("X-Forwarded-Proto", "https")

	// Without JAM_TRUST_PROXY the forwarded proto is ignored.
	if got := requestOrigin(r); got != "http://example.com" {
		t.Errorf("Expected http://example.com, got %s", got)
	}

	config.TrustProxy = true
	t.Cleanup(func() { config.TrustProxy = false })
	if got := requestOrigin(r); got != "https://example.com" {
		t.Errorf("Expected https://example.com, got %s", got)
	}

	// An explicit public origin wins over request headers.
	config.PublicOrigin = "https://party.example.com"
	t.Cleanup(func() { config.PublicOrigin = "" })
	if got := requestOrigin(r); got != "https://party.example.com" {
		t.Errorf("Expected https://party.example.com, got %s", got)
	}

	// When unset it falls back to inference.
	config.PublicOrigin = ""
	if got := requestOrigin(r); got != "https://example.com" {
		t.Errorf("Expected fallback to https://example.com, got %s", got)
	}
}

func TestInviteDeepLinkUsesPublicOrigin(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	p, err := store.Create()
	if err != nil {
		t.Fatalf("Party creation failed: %v", err)
	}

	config.PublicOrigin = "https://party.example.com"
	t.Cleanup(func() { config.PublicOrigin = "" })

	res, err := http.Get(ts.URL + "/invite/" + p.Code)
	if err != nil {
		t.Fatalf("GET /invite/%s failed: %v", p.Code, err)
	}
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(res.Body)
	content := buf.String()

	if !strings.Contains(content, "server=https%3A%2F%2Fparty.example.com") {
		t.Errorf("Expected deep link to carry the public origin, got: %s", content)
	}
	if strings.Contains(content, "server=http%3A") {
		t.Errorf("Expected no http server URL in deep link, got: %s", content)
	}
}

func TestInviteLanding(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// 1. Non-existent party
	res, err := http.Get(ts.URL + "/invite/ZZZZZZ")
	if err != nil {
		t.Fatalf("GET /invite/ZZZZZZ failed: %v", err)
	}
	if res.StatusCode != http.StatusNotFound {
		t.Errorf("Expected 404 for non-existent party, got %d", res.StatusCode)
	}

	// 2. Create an active party directly in store
	p, err := store.Create()
	if err != nil {
		t.Fatalf("Party creation failed: %v", err)
	}
	code := p.Code

	// 3. Active party landing page
	resActive, err := http.Get(ts.URL + "/invite/" + code)
	if err != nil {
		t.Fatalf("GET /invite/%s failed: %v", code, err)
	}
	if resActive.StatusCode != http.StatusOK {
		t.Errorf("Expected 200 for active party invite, got %d", resActive.StatusCode)
	}
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(resActive.Body)
	content := buf.String()

	expectedDeepLinkPrefix := "pulsr://party/" + code
	if !strings.Contains(content, expectedDeepLinkPrefix) {
		t.Errorf("Expected HTML content to contain deep link %s", expectedDeepLinkPrefix)
	}
	if !strings.Contains(content, code) {
		t.Errorf("Expected HTML content to contain party code %s", code)
	}
}

func TestInviteLandingOmitsTrackAndDoesNotDoubleEscape(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	p, err := store.Create()
	if err != nil {
		t.Fatalf("Party creation failed: %v", err)
	}
	p.Lock()
	p.Playback.SetTrack(nil, trackForTest("sec", "Secret Song", "Secret Artist"), 0, true, nil, nil)
	p.Unlock()

	res, err := http.Get(ts.URL + "/invite/" + p.Code)
	if err != nil {
		t.Fatalf("GET /invite/%s failed: %v", p.Code, err)
	}
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(res.Body)
	content := buf.String()
	if strings.Contains(content, "Secret Song") || strings.Contains(content, "Secret Artist") {
		t.Errorf("Expected /invite to omit active track metadata, got: %s", content)
	}

	resBad, err := http.Get(ts.URL + "/invite/A&B")
	if err != nil {
		t.Fatalf("GET /invite/A&B failed: %v", err)
	}
	badBuf := new(bytes.Buffer)
	_, _ = badBuf.ReadFrom(resBad.Body)
	if strings.Contains(badBuf.String(), "&amp;amp;") {
		t.Errorf("Expected code not to be double-escaped, got: %s", badBuf.String())
	}
}

func trackForTest(id, title, artist string) *party.Track {
	return &party.Track{VideoId: id, Title: title, Artist: artist}
}

func TestKickFlushesByeFrameBeforeClose(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// Create Party (Host)
	hostBody, _ := json.Marshal(map[string]string{
		"userId": "u_host", "deviceId": "d_host", "displayName": "Host",
	})
	res, _ := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(hostBody))
	var hostResp map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&hostResp)
	code := hostResp["code"].(string)
	hostToken := hostResp["token"].(string)

	// Join Party (Guest)
	guestBody, _ := json.Marshal(map[string]string{
		"userId": "u_guest", "deviceId": "d_guest", "displayName": "Guest",
	})
	gRes, _ := http.Post(fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), "application/json", bytes.NewReader(guestBody))
	var guestResp map[string]interface{}
	_ = json.NewDecoder(gRes.Body).Decode(&guestResp)
	guestToken := guestResp["token"].(string)
	guestYou := guestResp["you"].(map[string]interface{})
	guestMemberId := guestYou["memberId"].(string)

	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = fmt.Sprintf("/ws/parties/%s", code)

	dialWithToken := func(tok string) *websocket.Conn {
		h := http.Header{}
		h.Set("Authorization", "Bearer "+tok)
		c, _, err := websocket.DefaultDialer.Dial(u.String(), h)
		if err != nil {
			t.Fatalf("dial failed: %v", err)
		}
		return c
	}

	hostWS := dialWithToken(hostToken)
	defer hostWS.Close()
	guestWS := dialWithToken(guestToken)
	defer guestWS.Close()

	// Drain initial welcome frame on guest
	var welcome map[string]interface{}
	_ = guestWS.SetReadDeadline(time.Now().Add(2 * time.Second))
	_ = guestWS.ReadJSON(&welcome)

	// Host kicks guest
	kickFrame := map[string]interface{}{
		"type":     protocol.FrameControl,
		"action":   protocol.ActionKick,
		"memberId": guestMemberId,
	}
	if err := hostWS.WriteJSON(kickFrame); err != nil {
		t.Fatalf("failed to send kick: %v", err)
	}

	var gotBye bool
	for i := 0; i < 6; i++ {
		_ = guestWS.SetReadDeadline(time.Now().Add(2 * time.Second))
		var msg map[string]interface{}
		if err := guestWS.ReadJSON(&msg); err != nil {
			break
		}
		if msg["type"] == protocol.FrameBye && msg["reason"] == "kicked" {
			gotBye = true
			break
		}
	}
	if !gotBye {
		t.Fatalf("Expected kicked member to receive FrameBye with reason=kicked before socket close")
	}
}

func TestReconnectDoesNotMarkLiveMemberDisconnected(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	hostBody, _ := json.Marshal(map[string]string{
		"userId": "u_rc", "deviceId": "d_rc", "displayName": "Reconnector",
	})
	res, _ := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(hostBody))
	var hostResp map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&hostResp)
	code := hostResp["code"].(string)
	token := hostResp["token"].(string)

	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = fmt.Sprintf("/ws/parties/%s", code)
	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)

	ws1, _, err := websocket.DefaultDialer.Dial(u.String(), headers)
	if err != nil {
		t.Fatalf("first dial failed: %v", err)
	}
	defer ws1.Close()
	var w1 map[string]interface{}
	_ = ws1.SetReadDeadline(time.Now().Add(2 * time.Second))
	_ = ws1.ReadJSON(&w1)

	// Open second WebSocket with same member token (superseding ws1 in Hub)
	ws2, _, err := websocket.DefaultDialer.Dial(u.String(), headers)
	if err != nil {
		t.Fatalf("second dial failed: %v", err)
	}
	defer ws2.Close()
	var w2 map[string]interface{}
	_ = ws2.SetReadDeadline(time.Now().Add(2 * time.Second))
	_ = ws2.ReadJSON(&w2)

	// Give ws1's defer time to execute after Hub.Attach closed it
	time.Sleep(80 * time.Millisecond)

	p := store.Find(code)
	p.Lock()
	host := p.Host()
	connected := host != nil && host.Connected
	p.Unlock()
	if !connected {
		t.Fatalf("Expected member to remain Connected=true after ws1 defer ran")
	}
}

func TestJoinPreviewGetInviteRateLimited(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// Create a party first
	createBody, _ := json.Marshal(map[string]string{
		"userId": "u_rl", "deviceId": "d_rl", "displayName": "Host",
	})
	res, err := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(createBody))
	if err != nil || res.StatusCode != http.StatusCreated {
		t.Fatalf("create failed: status=%v err=%v", res.StatusCode, err)
	}
	var pResp map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&pResp)
	code := pResp["code"].(string)
	token := pResp["token"].(string)

	// Tighten joinLimiter to 2/min and verify 3rd /join returns 429.
	joinLimiter = newIPRateLimiter(time.Minute, 2, 100)
	for i := 0; i < 3; i++ {
		jb, _ := json.Marshal(map[string]string{
			"userId":      fmt.Sprintf("u_j_%d", i),
			"deviceId":    fmt.Sprintf("d_j_%d", i),
			"displayName": "Guest",
		})
		jr, err := http.Post(fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), "application/json", bytes.NewReader(jb))
		if err != nil {
			t.Fatalf("join %d failed: %v", i, err)
		}
		if i < 2 && jr.StatusCode != http.StatusOK {
			t.Fatalf("join %d status=%d, want 200", i, jr.StatusCode)
		}
		if i == 2 && jr.StatusCode != http.StatusTooManyRequests {
			t.Fatalf("join %d status=%d, want 429", i, jr.StatusCode)
		}
	}

	// Tighten readLimiter to 3/min across /preview, /get, /invite: 4th read must return 429.
	readLimiter = newIPRateLimiter(time.Minute, 3, 100)

	r1, _ := http.Get(fmt.Sprintf("%s/api/parties/%s/preview", ts.URL, code))
	if r1.StatusCode != http.StatusOK {
		t.Fatalf("/preview status=%d, want 200", r1.StatusCode)
	}

	req2, _ := http.NewRequest("GET", fmt.Sprintf("%s/api/parties/%s", ts.URL, code), nil)
	req2.Header.Set("Authorization", "Bearer "+token)
	r2, _ := http.DefaultClient.Do(req2)
	if r2.StatusCode != http.StatusOK {
		t.Fatalf("/get status=%d, want 200", r2.StatusCode)
	}

	r3, _ := http.Get(fmt.Sprintf("%s/invite/%s", ts.URL, code))
	if r3.StatusCode != http.StatusOK {
		t.Fatalf("/invite status=%d, want 200", r3.StatusCode)
	}

	// Next calls across /preview, /get, /invite must all be 429.
	for _, urlPath := range []string{
		fmt.Sprintf("%s/api/parties/%s/preview", ts.URL, code),
		fmt.Sprintf("%s/api/parties/%s", ts.URL, code),
		fmt.Sprintf("%s/invite/%s", ts.URL, code),
	} {
		req, _ := http.NewRequest("GET", urlPath, nil)
		req.Header.Set("Authorization", "Bearer "+token)
		rr, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("request %s failed: %v", urlPath, err)
		}
		if rr.StatusCode != http.StatusTooManyRequests {
			t.Fatalf("%s returned status=%d, want 429", urlPath, rr.StatusCode)
		}
	}
}

func TestRejoinClosesSupersededWebSocketAndPreservesRetryGrace(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// Host creates party, guest joins with tok1.
	hostBody, _ := json.Marshal(map[string]string{"userId": "uh", "deviceId": "dh", "displayName": "Host"})
	hRes, _ := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(hostBody))
	var hResp map[string]interface{}
	_ = json.NewDecoder(hRes.Body).Decode(&hResp)
	code := hResp["code"].(string)

	guestPayload := map[string]string{"userId": "ug", "deviceId": "dg", "displayName": "Guest"}
	gb, _ := json.Marshal(guestPayload)
	gRes, err := http.Post(fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), "application/json", bytes.NewReader(gb))
	if err != nil || gRes.StatusCode != http.StatusOK {
		t.Fatalf("initial join failed: status=%v err=%v", gRes.StatusCode, err)
	}
	var gResp map[string]interface{}
	_ = json.NewDecoder(gRes.Body).Decode(&gResp)
	tok1 := gResp["token"].(string)

	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = fmt.Sprintf("/ws/parties/%s", code)

	dialWS := func(tok string) *websocket.Conn {
		h := http.Header{}
		h.Set("Authorization", "Bearer "+tok)
		c, _, err := websocket.DefaultDialer.Dial(u.String(), h)
		if err != nil {
			t.Fatalf("dial failed: %v", err)
		}
		var welcome map[string]interface{}
		_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
		if err := c.ReadJSON(&welcome); err != nil {
			t.Fatalf("read welcome failed: %v", err)
		}
		return c
	}

	ws1 := dialWS(tok1)
	defer ws1.Close()

	// Rejoin via POST /join with tok1: must close superseded ws1 and rotate token.
	rejoinReq, _ := http.NewRequest("POST", fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), bytes.NewReader(gb))
	rejoinReq.Header.Set("Content-Type", "application/json")
	rejoinReq.Header.Set("Authorization", "Bearer "+tok1)
	rjRes, err := http.DefaultClient.Do(rejoinReq)
	if err != nil || rjRes.StatusCode != http.StatusOK {
		t.Fatalf("rejoin failed: status=%v err=%v", rjRes.StatusCode, err)
	}
	var rjResp map[string]interface{}
	_ = json.NewDecoder(rjRes.Body).Decode(&rjResp)
	tok2 := rjResp["token"].(string)
	if tok2 == tok1 {
		t.Fatalf("expected token rotation on rejoin")
	}

	// Superseded ws1 must close promptly without sending FrameBye (which would make clients leaveParty).
	_ = ws1.SetReadDeadline(time.Now().Add(2 * time.Second))
	for {
		var msg map[string]interface{}
		err := ws1.ReadJSON(&msg)
		if err != nil {
			break
		}
		if msg["type"] == protocol.FrameBye {
			t.Fatalf("superseded rejoin socket should close cleanly without FrameBye, got %+v", msg)
		}
	}

	// Retried join still presenting tok1 within grace window must succeed (no 401 bad_token).
	retryReq, _ := http.NewRequest("POST", fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), bytes.NewReader(gb))
	retryReq.Header.Set("Content-Type", "application/json")
	retryReq.Header.Set("Authorization", "Bearer "+tok1)
	rtRes, err := http.DefaultClient.Do(retryReq)
	if err != nil || rtRes.StatusCode != http.StatusOK {
		t.Fatalf("retried join with grace token failed: status=%v err=%v", rtRes.StatusCode, err)
	}
	var rtResp map[string]interface{}
	_ = json.NewDecoder(rtRes.Body).Decode(&rtResp)
	tok3 := rtResp["token"].(string)

	ws2 := dialWS(tok3)
	defer ws2.Close()
}

func TestWebSocketSetAutoplayAndQueueRemoveIndexAndSweepBye(t *testing.T) {
	ts := setupTestServer()
	defer ts.Close()

	// Create Party (Host)
	hostBody, _ := json.Marshal(map[string]string{
		"userId": "u_h", "deviceId": "d_h", "displayName": "Host",
	})
	res, _ := http.Post(ts.URL+"/api/parties", "application/json", bytes.NewReader(hostBody))
	var hostResp map[string]interface{}
	_ = json.NewDecoder(res.Body).Decode(&hostResp)
	code := hostResp["code"].(string)
	hostToken := hostResp["token"].(string)

	// Join Party (Guest)
	guestBody, _ := json.Marshal(map[string]string{
		"userId": "u_g", "deviceId": "d_g", "displayName": "Guest",
	})
	gRes, _ := http.Post(fmt.Sprintf("%s/api/parties/%s/join", ts.URL, code), "application/json", bytes.NewReader(guestBody))
	var guestResp map[string]interface{}
	_ = json.NewDecoder(gRes.Body).Decode(&guestResp)
	guestToken := guestResp["token"].(string)

	u, _ := url.Parse(ts.URL)
	u.Scheme = "ws"
	u.Path = fmt.Sprintf("/ws/parties/%s", code)
	dial := func(tok string) *websocket.Conn {
		h := http.Header{}
		h.Set("Authorization", "Bearer "+tok)
		c, _, err := websocket.DefaultDialer.Dial(u.String(), h)
		if err != nil {
			t.Fatalf("dial failed: %v", err)
		}
		var w map[string]interface{}
		_ = c.SetReadDeadline(time.Now().Add(2 * time.Second))
		_ = c.ReadJSON(&w)
		return c
	}

	hostWS := dial(hostToken)
	defer hostWS.Close()
	guestWS := dial(guestToken)
	defer guestWS.Close()

	// 1. SetAutoplay must bump seq in broadcast state frame.
	if err := hostWS.WriteJSON(map[string]interface{}{
		"type":    protocol.FrameControl,
		"action":  protocol.ActionSetAutoplay,
		"enabled": true,
	}); err != nil {
		t.Fatalf("send setAutoplay failed: %v", err)
	}

	var gotAutoplayState bool
	for i := 0; i < 6; i++ {
		_ = guestWS.SetReadDeadline(time.Now().Add(2 * time.Second))
		var f map[string]interface{}
		if err := guestWS.ReadJSON(&f); err != nil {
			break
		}
		if f["type"] == protocol.FrameState {
			pb, _ := f["playback"].(map[string]interface{})
			if pb["autoplayEnabled"] == true && pb["seq"].(float64) >= 1 {
				gotAutoplayState = true
				break
			}
		}
	}
	if !gotAutoplayState {
		t.Fatalf("expected guest to receive state frame with autoplayEnabled=true and seq >= 1")
	}

	// 2. SetQueue [t0, t1, t2] at queueIndex=1, then test queueRemove by index.
	if err := hostWS.WriteJSON(map[string]interface{}{
		"type":   protocol.FrameControl,
		"action": protocol.ActionSetQueue,
		"queue": []map[string]interface{}{
			{"videoId": "t0", "title": "T0"},
			{"videoId": "t1", "title": "T1"},
			{"videoId": "t2", "title": "T2"},
		},
		"queueIndex": 1,
	}); err != nil {
		t.Fatalf("send setQueue failed: %v", err)
	}

	// Wait until host receives queue frame
	for i := 0; i < 6; i++ {
		_ = hostWS.SetReadDeadline(time.Now().Add(2 * time.Second))
		var f map[string]interface{}
		if err := hostWS.ReadJSON(&f); err != nil {
			break
		}
		if f["type"] == protocol.FrameQueue {
			break
		}
	}

	// Index 0 (history) and Index 1 (playing) must be rejected with FrameError.
	for _, badIdx := range []int{0, 1} {
		if err := hostWS.WriteJSON(map[string]interface{}{
			"type":   protocol.FrameControl,
			"action": protocol.ActionQueueRemove,
			"index":  badIdx,
		}); err != nil {
			t.Fatalf("send queueRemove badIdx=%d failed: %v", badIdx, err)
		}
		var gotErr bool
		for i := 0; i < 4; i++ {
			_ = hostWS.SetReadDeadline(time.Now().Add(2 * time.Second))
			var f map[string]interface{}
			if err := hostWS.ReadJSON(&f); err != nil {
				break
			}
			if f["type"] == protocol.FrameError && f["error"] == "not_found" {
				gotErr = true
				break
			}
		}
		if !gotErr {
			t.Fatalf("expected not_found error when removing queue index %d", badIdx)
		}
	}

	// Index 2 (upcoming) must succeed.
	if err := hostWS.WriteJSON(map[string]interface{}{
		"type":   protocol.FrameControl,
		"action": protocol.ActionQueueRemove,
		"index":  2,
	}); err != nil {
		t.Fatalf("send queueRemove index=2 failed: %v", err)
	}
	var removedOK bool
	for i := 0; i < 6; i++ {
		_ = hostWS.SetReadDeadline(time.Now().Add(2 * time.Second))
		var f map[string]interface{}
		if err := hostWS.ReadJSON(&f); err != nil {
			break
		}
		if f["type"] == protocol.FrameQueue {
			q, _ := f["queue"].(map[string]interface{})
			items, _ := q["items"].([]interface{})
			if len(items) == 2 {
				removedOK = true
				break
			}
		}
	}
	if !removedOK {
		t.Fatalf("expected queueRemove index=2 to leave 2 tracks in queue")
	}

	// 3. Expire the party and run sweepOnce: guest must receive bye with reason=expired.
	p := store.Find(code)
	p.Lock()
	p.CreatedAtMs = clock.NowMs() - config.PartyMaxAgeMs - 1000
	p.Unlock()

	sweepOnce(clock.NowMs())

	if store.Find(code) != nil {
		t.Fatalf("expected expired party to be removed from store")
	}

	var gotExpiredBye bool
	for i := 0; i < 8; i++ {
		_ = guestWS.SetReadDeadline(time.Now().Add(2 * time.Second))
		var f map[string]interface{}
		if err := guestWS.ReadJSON(&f); err != nil {
			break
		}
		if f["type"] == protocol.FrameBye && f["reason"] == "expired" {
			gotExpiredBye = true
			break
		}
	}
	if !gotExpiredBye {
		t.Fatalf("expected connected client to receive bye with reason=expired before close")
	}
}

func TestActivityFrameDetails(t *testing.T) {
	m := &party.Member{DisplayName: "Alice"}

	// Single frame["track"] on ActionQueueAdd
	afSingle := activityFrame(m, protocol.ActionQueueAdd, map[string]interface{}{
		"track": map[string]interface{}{"videoId": "v1", "title": "Blue Horizon"},
	})
	if afSingle["detail"] != `Added "Blue Horizon" to the queue` {
		t.Fatalf("unexpected single queueAdd detail: %v", afSingle["detail"])
	}

	// Array frame["tracks"] on ActionQueueAdd
	afMulti := activityFrame(m, protocol.ActionQueueAdd, map[string]interface{}{
		"tracks": []interface{}{
			map[string]interface{}{"videoId": "v1", "title": "Song One"},
			map[string]interface{}{"videoId": "v2", "title": "Song Two"},
		},
	})
	if afMulti["detail"] != `Added "Song One" and 1 more to the queue` {
		t.Fatalf("unexpected multi queueAdd detail: %v", afMulti["detail"])
	}

	// ActionSetHostOnlyControl true & false
	afHostOn := activityFrame(m, protocol.ActionSetHostOnlyControl, map[string]interface{}{"enabled": true})
	if afHostOn["detail"] != "Restricted playback controls to the host" {
		t.Fatalf("unexpected hostOnly true detail: %v", afHostOn["detail"])
	}
	afHostOff := activityFrame(m, protocol.ActionSetHostOnlyControl, map[string]interface{}{"enabled": false})
	if afHostOff["detail"] != "Allowed everyone to control playback" {
		t.Fatalf("unexpected hostOnly false detail: %v", afHostOff["detail"])
	}
}
