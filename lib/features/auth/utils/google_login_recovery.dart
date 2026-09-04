// lib/features/auth/utils/google_login_recovery.dart
//
// Pure state machine behind the Google sign-in block recovery ladder in
// ytm_web_login_sheet.dart. Kept free of Flutter/webview dependencies so the
// ladder can be unit-tested in isolation.
//
// Ladder (max [maxAttempts] automatic retries, never loops):
//   block #1 → clear cookies+cache, switch identity desktop → mobile, reload
//   block #2 → clear cookies+cache, switch identity mobile → desktop, reload
//   block #3 → null (exhausted; the sheet shows the manual recovery card)

/// Which browser identity the embedded WebView currently presents.
enum BrowserIdentity { desktop, mobile }

/// One rung of the recovery ladder: the identity to switch to before
/// reloading (cookies/cache clearing is implied and performed by the caller).
class BlockRecoveryStep {
  final BrowserIdentity nextIdentity;

  const BlockRecoveryStep(this.nextIdentity);
}

class GoogleBlockRecovery {
  final int maxAttempts;
  BrowserIdentity _identity;
  int _attempt = 0;

  GoogleBlockRecovery({
    this.maxAttempts = 2,
    BrowserIdentity initialIdentity = BrowserIdentity.desktop,
  }) : _identity = initialIdentity;

  BrowserIdentity get identity => _identity;
  int get attempt => _attempt;
  bool get exhausted => _attempt >= maxAttempts;

  /// Called when a Google block page is detected. Returns the next recovery
  /// step, or null when automatic retries are exhausted (stop — never loop).
  BlockRecoveryStep? onBlocked() {
    if (exhausted) return null;
    _attempt++;
    _identity = _identity == BrowserIdentity.desktop
        ? BrowserIdentity.mobile
        : BrowserIdentity.desktop;
    return BlockRecoveryStep(_identity);
  }

  /// Manual retry (recovery card): clear the automatic attempts so the full
  /// ladder can run again. Keeps the currently selected identity.
  void reset() => _attempt = 0;
}
