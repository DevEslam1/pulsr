// lib/features/dlna/upnp_entities.dart

/// Decodes standard XML and numeric character entity references in [value].
///
/// Validates numeric code points (`code >= 0 && code <= 0x10FFFF && !(code >= 0xD800 && code <= 0xDFFF)`)
/// before calling [String.fromCharCode]; malformed or out-of-range entities are left intact.
String decodeXmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(
    RegExp(r'&(#x?[0-9A-Fa-f]+|[A-Za-z]+);'),
    (match) {
      final token = match.group(1) ?? '';
      switch (token) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final int? code;
      if (token.startsWith('#x') || token.startsWith('#X')) {
        code = int.tryParse(token.substring(2), radix: 16);
      } else if (token.startsWith('#')) {
        code = int.tryParse(token.substring(1));
      } else {
        code = null;
      }
      if (code != null &&
          code >= 0 &&
          code <= 0x10FFFF &&
          !(code >= 0xD800 && code <= 0xDFFF)) {
        return String.fromCharCode(code);
      }
      return match.group(0)!;
    },
  );
}
