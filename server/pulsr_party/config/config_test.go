package config

import (
	"net/netip"
	"testing"
)

func TestGetOrigin(t *testing.T) {
	t.Setenv("JAM_PUBLIC_ORIGIN", " https://party.example.com/ ")
	if got := getOrigin("JAM_PUBLIC_ORIGIN"); got != "https://party.example.com" {
		t.Errorf("Expected https://party.example.com, got %q", got)
	}

	t.Setenv("JAM_PUBLIC_ORIGIN", "party.example.com")
	if got := getOrigin("JAM_PUBLIC_ORIGIN"); got != "" {
		t.Errorf("Expected a non-http(s) origin to be ignored, got %q", got)
	}

	t.Setenv("JAM_PUBLIC_ORIGIN", "https://party.example.com/invite")
	if got := getOrigin("JAM_PUBLIC_ORIGIN"); got != "" {
		t.Errorf("Expected an origin with a path to be ignored, got %q", got)
	}

	for _, bad := range []string{"https://party.example.com?a=b", "https://party.example.com#frag", "https://user@party.example.com"} {
		t.Setenv("JAM_PUBLIC_ORIGIN", bad)
		if got := getOrigin("JAM_PUBLIC_ORIGIN"); got != "" {
			t.Errorf("Expected %q to be ignored, got %q", bad, got)
		}
	}

	t.Setenv("JAM_PUBLIC_ORIGIN", "")
	if got := getOrigin("JAM_PUBLIC_ORIGIN"); got != "" {
		t.Errorf("Expected an unset origin to be empty, got %q", got)
	}
}

func TestGetInt(t *testing.T) {
	t.Setenv("BITCHORD_TEST_INT", "")
	if got := getInt("BITCHORD_TEST_INT", 7); got != 7 {
		t.Errorf("unset = %d, want 7", got)
	}
	t.Setenv("BITCHORD_TEST_INT", "25")
	if got := getInt("BITCHORD_TEST_INT", 7); got != 25 {
		t.Errorf("got %d, want 25", got)
	}
	t.Setenv("BITCHORD_TEST_INT", "  30 ")
	if got := getInt("BITCHORD_TEST_INT", 7); got != 30 {
		t.Errorf("padded value = %d, want 30", got)
	}
	t.Setenv("BITCHORD_TEST_INT", "not-a-number")
	if got := getInt("BITCHORD_TEST_INT", 7); got != 7 {
		t.Errorf("malformed = %d, want fallback 7", got)
	}
}

func TestGetCSV(t *testing.T) {
	t.Setenv("BITCHORD_TEST_CSV", "")
	if got := getCSV("BITCHORD_TEST_CSV", ""); got != nil {
		t.Errorf("empty = %v, want nil", got)
	}
	t.Setenv("BITCHORD_TEST_CSV", "https://a.example, https://b.example")
	got := getCSV("BITCHORD_TEST_CSV", "")
	if len(got) != 2 || got[0] != "https://a.example" || got[1] != "https://b.example" {
		t.Errorf("got %v, want two trimmed origins", got)
	}
	t.Setenv("BITCHORD_TEST_CSV", "a,, ,b")
	got = getCSV("BITCHORD_TEST_CSV", "")
	if len(got) != 2 {
		t.Errorf("blank entries not skipped: %v", got)
	}
	t.Setenv("BITCHORD_TEST_CSV", "")
	got = getCSV("BITCHORD_TEST_CSV", "x,y")
	if len(got) != 2 {
		t.Errorf("fallback not used: %v", got)
	}
}

func TestGetBool(t *testing.T) {
	t.Setenv("BITCHORD_TEST_BOOL", "")
	if got := getBool("BITCHORD_TEST_BOOL", true); got != true {
		t.Errorf("unset = %v, want fallback true", got)
	}
	t.Setenv("BITCHORD_TEST_BOOL", "true")
	if got := getBool("BITCHORD_TEST_BOOL", false); got != true {
		t.Errorf("got %v, want true", got)
	}
	t.Setenv("BITCHORD_TEST_BOOL", "0")
	if got := getBool("BITCHORD_TEST_BOOL", true); got != false {
		t.Errorf("got %v, want false", got)
	}
	t.Setenv("BITCHORD_TEST_BOOL", "yes-please")
	if got := getBool("BITCHORD_TEST_BOOL", true); got != true {
		t.Errorf("malformed = %v, want fallback true", got)
	}
}

func TestIsAllowedOrigin(t *testing.T) {
	old := AllowedOrigins
	AllowedOrigins = []string{"https://app.example", "https://admin.example"}
	defer func() { AllowedOrigins = old }()

	if !IsAllowedOrigin("https://app.example") {
		t.Errorf("listed origin rejected")
	}
	if IsAllowedOrigin("https://evil.example") {
		t.Errorf("unlisted origin allowed")
	}
	if IsAllowedOrigin("") {
		t.Errorf("empty origin allowed")
	}
}

func TestParseTrustedProxiesAndIsTrustedProxy(t *testing.T) {
	old := TrustedProxies
	defer func() { TrustedProxies = old }()

	TrustedProxies = ParseTrustedProxies([]string{
		"127.0.0.1/8",
		"::1",
		"10.20.30.40",
		"not-a-cidr",
	})
	if len(TrustedProxies) != 3 {
		t.Fatalf("expected 3 valid prefixes, got %d", len(TrustedProxies))
	}

	if !IsTrustedProxy(netip.MustParseAddr("127.0.0.5")) {
		t.Errorf("expected 127.0.0.5 to match 127.0.0.1/8")
	}
	if !IsTrustedProxy(netip.MustParseAddr("::ffff:10.20.30.40")) {
		t.Errorf("expected mapped IPv4 to match 10.20.30.40")
	}
	if !IsTrustedProxy(netip.MustParseAddr("::1")) {
		t.Errorf("expected ::1 to match")
	}
	if IsTrustedProxy(netip.MustParseAddr("203.0.113.5")) {
		t.Errorf("expected public IP not to match trusted proxies")
	}
	if IsTrustedProxy(netip.Addr{}) {
		t.Errorf("expected invalid addr not to match")
	}
}
