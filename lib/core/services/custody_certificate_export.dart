import 'dart:convert';
import 'dart:io';

import 'chain_of_custody_service.dart';

/// Where a written certificate lives and the exact bytes it contains.
class CustodyCertificateArtifact {
  final File file;
  final String jsonText;
  final String certificateSha256;

  const CustodyCertificateArtifact({
    required this.file,
    required this.jsonText,
    required this.certificateSha256,
  });
}

/// Writes a chain-of-custody certificate as a standalone JSON artifact that a
/// third party can check without trusting the app that produced it.
///
/// The certificate deliberately carries a file's SHA-256, size and mtime but NOT
/// its path: the digest is what makes the claim verifiable, and the path would
/// only leak where the user keeps their music.
Future<CustodyCertificateArtifact> exportCustodyCertificate(
  ChainOfCustodyReport report, {
  required Directory directory,
}) async {
  final jsonText = const JsonEncoder.withIndent('  ').convert(report.toJson());
  final name = 'pulsr-certificate-${_safe(report.trackId)}-'
      '${report.verifiedAt.toUtc().millisecondsSinceEpoch}.json';
  await directory.create(recursive: true);
  final file = File(directory.path + Platform.pathSeparator + name);
  await file.writeAsString(jsonText, flush: true);

  // Round-trip guard: an artifact whose embedded digest no longer matches its own
  // fields was not written correctly, and must not be handed out as evidence.
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final writtenDigest = decoded['certificateSha256'] as String?;
  if (writtenDigest != report.certificateSha256) {
    throw StateError(
        'Certificate digest mismatch (expected ${report.certificateSha256}, '
        'artifact carries $writtenDigest)');
  }

  return CustodyCertificateArtifact(
    file: file,
    jsonText: jsonText,
    certificateSha256: report.certificateSha256,
  );
}

/// Filenames must survive whatever track ids the library contains, without
/// becoming path traversal input. Separators and other punctuation are replaced,
/// and any surviving leading dots are stripped — `.._.._x` cannot traverse, but a
/// leading dot hides the file on Unix and reads like a parent reference.
String _safe(String value) {
  final filtered = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final trimmed = filtered.replaceFirst(RegExp(r'^\.+'), '');
  final name = trimmed.isEmpty ? 'track' : trimmed;
  return name.length <= 40 ? name : name.substring(0, 40);
}
