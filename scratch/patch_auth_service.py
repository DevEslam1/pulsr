import pathlib
import re
import sys

path = pathlib.Path("lib/core/services/auth_service.dart")
src = path.read_text(encoding="utf-8")

pattern = re.compile(
    r"      final authz = await googleUser\.authorizationClient\r?\n"
    r"          \.authorizationForScopes\(\['email'\]\)\.timeout\(_operationTimeout\);\r?\n"
    r"      final OAuthCredential credential = GoogleAuthProvider\.credential\(\r?\n"
    r"        accessToken:[^\n]*\n"
    r"        idToken: googleAuth\.idToken,\r?\n"
    r"      \);"
)

replacement = """      // `authorizationForScopes` returns null whenever the cached grant needs
      // user interaction, so dereferencing it crashed the whole sign-in with a
      // null-check error before Firebase was ever called. The ID token is what
      // Firebase actually needs; the access token is optional.
      String? accessToken;
      try {
        final authz = await googleUser.authorizationClient
            .authorizationForScopes(['email']).timeout(_operationTimeout);
        accessToken = authz?.accessToken;
      } catch (e) {
        // Authorization is optional here: a valid ID token is sufficient.
      }

      final idToken = googleAuth.idToken;
      if ((idToken == null || idToken.isEmpty) &&
          (accessToken == null || accessToken.isEmpty)) {
        throw const AuthFailure(
          code: 'AUTH_GOOGLE_NO_CREDENTIAL',
          userMessage:
              'Google did not return a sign-in credential. Please try again.',
          kind: AuthFailureKind.googleUnavailable,
          recovery: AuthRecoveryAction.retry,
        );
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );"""

new, count = pattern.subn(replacement, src)
if count != 1:
    print(f"MATCHES={count}; aborting without writing")
    sys.exit(1)

path.write_text(new, encoding="utf-8")
print("patched auth_service.dart")
