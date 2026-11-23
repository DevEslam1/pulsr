package config

import (
	"log"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
)

func getInt(key string, fallback int) int {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(strings.TrimSpace(val))
	if err != nil {
		return fallback
	}
	return parsed
}

func getCSV(key string, fallback string) []string {
	val := os.Getenv(key)
	if val == "" {
		val = fallback
	}
	if val == "" {
		return nil
	}
	var res []string
	for _, item := range strings.Split(val, ",") {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" {
			res = append(res, trimmed)
		}
	}
	return res
}

func getBool(key string, fallback bool) bool {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(strings.TrimSpace(val))
	if err != nil {
		return fallback
	}
	return parsed
}

func getOrigin(key string) string {
	val := strings.TrimRight(strings.TrimSpace(os.Getenv(key)), "/")
	if val == "" {
		return ""
	}
	u, err := url.Parse(val)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" || u.User != nil {
		log.Printf("%s %q is not an http(s) origin; ignoring", key, val)
		return ""
	}
	return val
}

// IsAllowedOrigin deliberately does not support a wildcard. Browser clients
// must be explicitly named; native clients send no Origin header.
func IsAllowedOrigin(origin string) bool {
	for _, allowed := range AllowedOrigins {
		if origin == allowed {
			return true
		}
	}
	return false
}

var (
	MaxMembers           = getInt("JAM_MAX_MEMBERS", 5)
	StateHeartbeatMs     = getInt("JAM_STATE_HEARTBEAT_MS", 5000)
	PlayLeadMs           = getInt("JAM_PLAY_LEAD_MS", 350)
	DisconnectGraceMs    = int64(getInt("JAM_DISCONNECT_GRACE_MS", 45000))
	EmptyPartyTTLMs      = int64(getInt("JAM_EMPTY_PARTY_TTL_MS", 120000))
	PartyMaxAgeMs        = int64(getInt("JAM_PARTY_MAX_AGE_MS", 12*60*60*1000))
	ControlRatePerSecond = float64(getInt("JAM_CONTROL_RATE_PER_SECOND", 25))
	MaxUpcomingQueue     = getInt("JAM_MAX_UPCOMING_QUEUE", 25)
	MaxQueueLength       = getInt("JAM_MAX_QUEUE_LENGTH", 1+MaxUpcomingQueue)
	// Render Free has 0.1 CPU. Fifty rooms (at most 250 sockets) is a safe
	// starting ceiling; raise it only after measuring CPU and memory usage.
	MaxParties           = getInt("JAM_MAX_PARTIES", 50)
	CreateRatePerMinute  = getInt("JAM_CREATE_RATE_PER_MINUTE", 2)
	JoinRatePerMinute    = getInt("JAM_JOIN_RATE_PER_MINUTE", 20)
	ReadRatePerMinute    = getInt("JAM_READ_RATE_PER_MINUTE", 60)
	RateLimitMaxEntries  = getInt("JAM_RATE_LIMIT_MAX_ENTRIES", 10000)
	TokenGraceMs         = int64(getInt("JAM_TOKEN_GRACE_MS", 30000))
	RequestMaxBytes      = int64(getInt("JAM_REQUEST_MAX_BYTES", 16*1024))
	WebSocketMaxBytes    = int64(getInt("JAM_WEBSOCKET_MAX_BYTES", 16*1024))
	ConnectionIdleMs     = int64(getInt("JAM_CONNECTION_IDLE_MS", 15*60*1000))
	FrameRatePerSecond   = float64(getInt("JAM_FRAME_RATE_PER_SECOND", 30))
	AllowedOrigins       = getCSV("JAM_ALLOWED_ORIGINS", "")
	TrustProxy           = getBool("JAM_TRUST_PROXY", false)
	TrustedProxyHops     = getInt("JAM_TRUST_PROXY_HOPS", 1)
	TrustedProxies       = ParseTrustedProxies(getCSV("JAM_TRUSTED_PROXIES", ""))
	ClientIPHeader       = strings.TrimSpace(os.Getenv("JAM_CLIENT_IP_HEADER"))
	PublicOrigin         = getOrigin("JAM_PUBLIC_ORIGIN")
	Port                 = getInt("PORT", 8000)
)

// ParseTrustedProxies parses a list of IP addresses or CIDR ranges representing
// trusted reverse proxies. Invalid entries are logged and ignored.
func ParseTrustedProxies(entries []string) []netip.Prefix {
	if len(entries) == 0 {
		return nil
	}
	var prefixes []netip.Prefix
	for _, raw := range entries {
		if p, err := netip.ParsePrefix(raw); err == nil {
			addr := p.Addr()
			if addr.Is4In6() {
				// Normalize IPv4-mapped IPv6 CIDR prefixes only when whole-host or keep unmapped.
				addr = addr.Unmap()
				bits := p.Bits() - 96
				if bits >= 0 && bits <= 32 {
					p = netip.PrefixFrom(addr, bits)
				}
			}
			prefixes = append(prefixes, p.Masked())
			continue
		}
		if addr, err := netip.ParseAddr(raw); err == nil {
			addr = addr.Unmap()
			prefixes = append(prefixes, netip.PrefixFrom(addr, addr.BitLen()))
			continue
		}
		log.Printf("JAM_TRUSTED_PROXIES entry %q is not a valid IP or CIDR; ignoring", raw)
	}
	return prefixes
}

// IsTrustedProxy reports whether addr falls within TrustedProxies.
func IsTrustedProxy(addr netip.Addr) bool {
	if !addr.IsValid() {
		return false
	}
	addr = addr.Unmap()
	for _, prefix := range TrustedProxies {
		if prefix.Contains(addr) {
			return true
		}
	}
	return false
}

// Open-app heartbeats. The interval is handed back on every ping, so it can be
// raised here under load without an app update. An install stays counted for
// one interval plus the grace period after its last ping.
var (
	PresenceIntervalSec     = getInt("JAM_PRESENCE_INTERVAL_SEC", 300)
	PresenceGraceSec        = getInt("JAM_PRESENCE_GRACE_SEC", 90)
	PresenceMaxEntries      = getInt("JAM_PRESENCE_MAX_ENTRIES", 200000)
	PresencePingsPerMinute  = getInt("JAM_PRESENCE_PINGS_PER_MINUTE", 20)
	PresenceRateLimitMaxIPs = getInt("JAM_PRESENCE_RATE_LIMIT_MAX_IPS", 100000)
)
