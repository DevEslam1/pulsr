package main

import (
	"flag"
	"fmt"
	"log"
	"math"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pulsr-audio/pulsr/server/party/clock"
	"github.com/pulsr-audio/pulsr/server/party/hub"
	"github.com/pulsr-audio/pulsr/server/party/party"
	"github.com/pulsr-audio/pulsr/server/party/protocol"
)

type LatencySample struct {
	RTTMs   float64
	DriftMs float64
}

func main() {
	clientCount := flag.Int("clients", 500, "Number of concurrent simulated WebSocket clients")
	targetURL := flag.String("url", "", "Target server base URL (e.g. http://localhost:8000). If empty, runs in-process")
	pingsPerClient := flag.Int("pings", 5, "Number of clock sync pings each client performs")
	flag.Parse()

	fmt.Printf("====================================================================\n")
	fmt.Printf("Pulsr Listen Together — WebSocket Load & Clock Drift Benchmark\n")
	fmt.Printf("Simulated Clients: %d | Pings/client: %d\n", *clientCount, *pingsPerClient)
	fmt.Printf("====================================================================\n")

	var baseURL string
	var cleanup func()

	if *targetURL != "" {
		baseURL = strings.TrimRight(*targetURL, "/")
		cleanup = func() {}
	} else {
		// Launch in-process test server supporting 500 clients in a high-capacity room
		h := hub.NewHub()
		pStore := party.NewPartyStore()
		p, err := pStore.CreateWithLimits(100, 1000)
		if err != nil {
			log.Fatalf("Failed to create party: %v", err)
		}

		upgrader := websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		}

		mux := http.NewServeMux()
		mux.HandleFunc("GET /ws/parties/{code}", func(w http.ResponseWriter, r *http.Request) {
			conn, err := upgrader.Upgrade(w, r, nil)
			if err != nil {
				return
			}
			memberId := fmt.Sprintf("u_%d", time.Now().UnixNano())
			sc := h.Attach(p.Code, memberId, conn)
			defer func() {
				h.Detach(p.Code, memberId, sc)
				_ = sc.Close()
			}()

			// Send welcome frame
			_ = sc.WriteJSON(map[string]interface{}{
				"type":     protocol.FrameWelcome,
				"version":  protocol.ProtocolVersion,
				"serverMs": clock.NowMs(),
			})

			for {
				var msg map[string]interface{}
				if err := conn.ReadJSON(&msg); err != nil {
					break
				}
				if msg["type"] == protocol.FramePing {
					_ = sc.WriteJSON(map[string]interface{}{
						"type":     protocol.FramePong,
						"clientMs": msg["clientMs"],
						"serverMs": clock.NowMs(),
					})
				}
			}
		})

		ts := httptest.NewServer(mux)
		baseURL = ts.URL
		cleanup = func() {
			h.CloseAll()
			ts.Close()
		}
	}
	defer cleanup()

	wsURL := "ws" + strings.TrimPrefix(baseURL, "http") + "/ws/parties/LOADTEST"

	var wg sync.WaitGroup
	var sampleMu sync.Mutex
	var samples []LatencySample
	var connectedCount int64
	var failedCount int64

	start := time.Now()

	for i := 0; i < *clientCount; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			// Slight stagger to avoid OS ephemeral port lock contention
			time.Sleep(time.Duration(id) * 2 * time.Millisecond)

			dialer := websocket.DefaultDialer
			var conn *websocket.Conn
			var err error
			for attempt := 0; attempt < 3; attempt++ {
				conn, _, err = dialer.Dial(wsURL, nil)
				if err == nil {
					break
				}
				time.Sleep(50 * time.Millisecond)
			}
			if err != nil {
				atomic.AddInt64(&failedCount, 1)
				return
			}
			defer conn.Close()
			atomic.AddInt64(&connectedCount, 1)

			// Wait for welcome frame
			var welcome map[string]interface{}
			_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
			if err := conn.ReadJSON(&welcome); err != nil {
				return
			}

			// Perform pings
			for p := 0; p < *pingsPerClient; p++ {
				tSend := clock.NowMs()
				pingMsg := map[string]interface{}{
					"type":     protocol.FramePing,
					"clientMs": tSend,
				}
				_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
				if err := conn.WriteJSON(pingMsg); err != nil {
					break
				}

				var pong map[string]interface{}
				_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
				if err := conn.ReadJSON(&pong); err != nil {
					break
				}

				tRecv := clock.NowMs()
				serverMs, ok := pong["serverMs"].(float64)
				if !ok {
					continue
				}

				rtt := float64(tRecv - tSend)
				// NTP 1-way delay assumption: estimated server time when pong received is serverMs + rtt/2
				estServerTime := serverMs + (rtt / 2.0)
				drift := math.Abs(estServerTime - float64(tRecv))

				sampleMu.Lock()
				samples = append(samples, LatencySample{
					RTTMs:   rtt,
					DriftMs: drift,
				})
				sampleMu.Unlock()

				time.Sleep(10 * time.Millisecond)
			}
		}(i)
	}

	wg.Wait()
	elapsed := time.Since(start)

	if len(samples) == 0 {
		log.Fatalf("No latency samples collected! Connected: %d, Failed: %d", connectedCount, failedCount)
	}

	rtts := make([]float64, len(samples))
	drifts := make([]float64, len(samples))
	var sumRTT, sumDrift float64

	for i, s := range samples {
		rtts[i] = s.RTTMs
		drifts[i] = s.DriftMs
		sumRTT += s.RTTMs
		sumDrift += s.DriftMs
	}

	sort.Float64s(rtts)
	sort.Float64s(drifts)

	p50Drift := percentile(drifts, 0.50)
	p90Drift := percentile(drifts, 0.90)
	p95Drift := percentile(drifts, 0.95)
	p99Drift := percentile(drifts, 0.99)

	p50RTT := percentile(rtts, 0.50)
	p90RTT := percentile(rtts, 0.90)
	p99RTT := percentile(rtts, 0.99)

	fmt.Printf("\n--- Benchmark Results ---\n")
	fmt.Printf("Total Elapsed:       %v\n", elapsed)
	fmt.Printf("Connected Clients:   %d / %d (%.1f%% success)\n", connectedCount, *clientCount, float64(connectedCount)*100/float64(*clientCount))
	fmt.Printf("Total Samples:       %d\n", len(samples))
	fmt.Printf("RTT (ms):            p50 = %.2f ms | p90 = %.2f ms | p99 = %.2f ms\n", p50RTT, p90RTT, p99RTT)
	fmt.Printf("Clock Drift (ms):    p50 = %.2f ms | p90 = %.2f ms | p95 = %.2f ms | p99 = %.2f ms\n", p50Drift, p90Drift, p95Drift, p99Drift)
	fmt.Printf("====================================================================\n")
}

func percentile(sorted []float64, pct float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(float64(len(sorted)-1) * pct)
	return sorted[idx]
}
