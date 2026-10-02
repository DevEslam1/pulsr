# ADR 010: Network Layer and Proxy Architecture

## Status
Accepted

## Context
Pulsr fetches online media through two different client stacks — Dart `HttpClient` (accounts, fallbacks, cache probes) and a native Kotlin/OkHttp extractor (the primary YTM path) — and it must honour user proxy settings, including authentication, across both. Additional constraints:
1. A hard-coded `DIRECT` bypass broke VPNs that expose themselves as a local proxy.
2. SOCKS5 cannot be spoken by Dart's `HttpClient`, but the native OkHttp stack can.
3. Connectivity must be checked cheaply before online work, and metered connections identified.
4. Proxy credentials are secrets and must not leak into logs.

## Decision
We model the proxy centrally and apply it per transport.

### 1. Proxy model (`lib/core/network/proxy_config.dart`)
- `ProxyConfig` holds `enabled`, `type` (`http` | `socks5`), `host`, `port`, `username`, `password`, `bypassHosts`, with `isValid`, `hasAuth` and `isBypassed(uri)`.
- `toFindProxyString(uri)` returns an HTTP `PROXY host:port; DIRECT` string, and deliberately returns `DIRECT` for SOCKS5 because Dart cannot speak SOCKS — the native extractor owns SOCKS instead of failing closed.
- Bypass matching requires a dot boundary so `*.example.com` does not match `fakeexample.com`; localhost aliases (`localhost`, `127.0.0.1`, `::1`) are treated as one class.
- `ProxyEntry` + `parse`/`parseList` import proxy lists from many formats (`host:port:user:pass`, URI forms, comma/tab/whitespace delimited, bracketed IPv6), with caps (10 MB text, 5000 entries) against pathological pastes.

### 2. Dart transport application (`app_http_overrides.dart`)
`AppHttpOverrides` extends `HttpOverrides` and installs a dynamic `findProxy` on every Dart client. When no custom proxy applies, it delegates to `HttpClient.findProxyFromEnvironment` (so VPN/environment proxies still work) rather than forcing `DIRECT`. `authenticateProxy` supplies credentials from the active config. `testConnection` probes through the configured path against `music.youtube.com` and treats a 4xx YouTube answer as "proxy path works, IP-level restriction" rather than a proxy failure.

### 3. Native transport
The Kotlin extractor applies SOCKS5 via OkHttp `Proxy.Type.SOCKS`; the interface is `IProxyApplier` (`lib/domain/interfaces/proxy_applier_interface.dart`), which returns a `bool` and is documented to **redact credentials** from logs/telemetry.

### 4. Connectivity (`connectivity_guard.dart`)
`ConnectivityGuard.hasConnection` is a pre-check for online fetches and fails open (`true`) on error so an unsupported platform does not block requests; `isMeteredConnection` identifies cellular-only connections for data-saving decisions.

### 5. Secret handling
Proxy passwords are stored via `FlutterSecureStorage` (see the DI `StorageModule`) and the settings state exposes only `hasProxyPassword` (a boolean), never the secret.

## Consequences
### Positive
- One proxy model applied consistently to Dart and native stacks; VPN/environment proxies are preserved.
- SOCKS5 is handled honestly by the transport that can speak it, with the Dart fallback documented as DIRECT.
- Proxies can be probed and bulk-imported safely.
- Credentials are kept out of logs and ordinary preferences.

### Negative / Trade-offs
- `AppHttpOverrides` is process-global, so per-request proxy overrides are not possible without bypassing it.
- Dart fallbacks do not traverse a configured SOCKS proxy; only the native extractor does.
