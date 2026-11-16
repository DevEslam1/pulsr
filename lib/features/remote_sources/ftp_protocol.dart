// lib/features/remote_sources/ftp_protocol.dart
//
// P0-1 "remote sources": wire-format parsing for FTP.
//
// Kept separate from the socket client so every format (multiline replies,
// UNIX and DOS listings, PASV and EPSV answers, MDTM timestamps) is a pure
// function that unit tests can drive without a server.
import 'dart:convert';

import '../../domain/models/remote_source.dart';

/// One complete FTP reply (`220`, `331 Password required`, `226-Done` ...).
class FtpReply {
  /// Creates a reply from its [code] and raw [lines].
  const FtpReply({required this.code, required this.lines});

  /// Numeric status code.
  final int code;

  /// Raw reply lines, first line included.
  final List<String> lines;

  /// Text after the status code on the final line.
  String get message {
    if (lines.isEmpty) return '';
    final last = lines.last;
    if (last.length <= 3) return '';
    final text = last.substring(3);
    return text.startsWith(' ') ? text.substring(1) : text;
  }

  /// `1xx`: the server accepted the command and more replies will follow.
  bool get isIntermediate => code >= 100 && code < 200;

  /// `2xx`: the command succeeded.
  bool get isSuccess => code >= 200 && code < 300;

  /// `3xx`: more information is required (password, offset accepted).
  bool get needsMoreInput => code >= 300 && code < 400;

  /// `4xx`: transient failure worth retrying.
  bool get isTransientFailure => code >= 400 && code < 500;

  /// `5xx`: permanent failure.
  bool get isPermanentFailure => code >= 500;

  /// Extracts the numeric code from [line], or `null` when it is not a reply.
  static int? codeOf(String line) {
    if (line.length < 3) return null;
    final code = int.tryParse(line.substring(0, 3));
    return code;
  }

  /// Reads one whole reply, pulling lines from [nextLine].
  ///
  /// Implements RFC 959 multiline replies: a first line with `-` in position 4
  /// keeps consuming lines until one starts with `<code> ` (or is exactly the
  /// code). Throws [FtpFormatError] for a malformed line and [FtpClosedError]
  /// when the server closes the connection mid-reply.
  static Future<FtpReply> readReply(
    Future<String?> Function() nextLine,
  ) async {
    final first = await nextLine();
    if (first == null) throw const FtpClosedError();
    final code = codeOf(first);
    if (code == null) throw FtpFormatError('Not an FTP reply: $first');
    final lines = <String>[first];
    var current = first;
    while (!isFinalLine(current, code)) {
      final next = await nextLine();
      if (next == null) throw const FtpClosedError();
      lines.add(next);
      current = next;
    }
    return FtpReply(code: code, lines: lines);
  }

  /// Whether [line] terminates a reply carrying [code].
  static bool isFinalLine(String line, int code) {
    final prefix = '$code';
    if (line.length == 3) return line == prefix;
    if (line.length < 4) return false;
    return line.startsWith(prefix) && line.codeUnitAt(3) == 0x20;
  }
}

/// The server closed the control connection.
class FtpClosedError implements Exception {
  /// Creates the error.
  const FtpClosedError();

  @override
  String toString() => 'FtpClosedError: the FTP server closed the connection';
}

/// The server sent a line that is not a valid FTP reply.
class FtpFormatError implements Exception {
  /// Creates the error for [line].
  const FtpFormatError(this.line);

  /// The offending line.
  final String line;

  @override
  String toString() => 'FtpFormatError: $line';
}

/// Parsers for the list-shaped FTP payloads.
abstract final class FtpListingParser {
  static const List<String> _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  static final RegExp _unixWithGroup = RegExp(
    r'^([-dlbcps])[-rwxStTs]{9}[.+@]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+'
    r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s+(.+)$',
  );
  static final RegExp _unixWithoutGroup = RegExp(
    r'^([-dlbcps])[-rwxStTs]{9}[.+@]?\s+\d+\s+\S+\s+(\d+)\s+'
    r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s+(.+)$',
  );
  static final RegExp _dos = RegExp(
    r'^(\d{2})-(\d{2})-(\d{2}|\d{4})\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?\s+'
    r'(<DIR>|\d+)\s+(.+)$',
  );

  /// Parses one `LIST` line into an entry, or returns `null` for headers and
  /// blank lines (`total 12` and similar).
  ///
  /// [parentPath] is the directory the listing was requested for; [now] is used
  /// to resolve the year of UNIX timestamps that only carry `HH:MM`.
  static RemoteEntry? parseLine(
    String line, {
    required String parentPath,
    DateTime? now,
  }) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) return null;
    final dos = _parseDos(trimmed, parentPath);
    if (dos != null) return dos;
    return _parseUnix(trimmed, parentPath, now ?? DateTime.now());
  }

  /// Parses a whole `LIST` payload.
  static List<RemoteEntry> parseListing(
    String output, {
    required String parentPath,
    DateTime? now,
  }) {
    final entries = <RemoteEntry>[];
    for (final line in LineSplitter.split(output)) {
      final entry = parseLine(line, parentPath: parentPath, now: now);
      if (entry != null) entries.add(entry);
    }
    entries.sort(RemoteEntry.compare);
    return entries;
  }

  /// Turns `NLST` output (names only) into entries with unknown size.
  ///
  /// [isDirectory] is unknown from NLST alone, so callers refine entries with
  /// `stat` when they can afford the round-trips.
  static List<RemoteEntry> parseNameList(
    String output, {
    required String parentPath,
  }) {
    final entries = <RemoteEntry>[];
    final seen = <String>{};
    for (final rawLine in LineSplitter.split(output)) {
      var name = rawLine.trim();
      if (name.isEmpty) continue;
      if (name == '.' || name == '..') continue;
      name = name.replaceAll('\\', '/');
      final slash = name.lastIndexOf('/');
      if (slash != -1) name = name.substring(slash + 1);
      if (name.isEmpty || !seen.add(name)) continue;
      entries.add(
        RemoteEntry(
          path: _join(parentPath, name),
          name: name,
          isDirectory: false,
        ),
      );
    }
    entries.sort(RemoteEntry.compare);
    return entries;
  }

  /// Parses a `227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)` answer.
  static ({String host, int port})? parsePassiveReply(String message) {
    final match = RegExp(
      r'(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,'
      r'\s*(\d{1,3})\s*,\s*(\d{1,3})',
    ).firstMatch(message);
    if (match == null) return null;
    final parts = <int>[];
    for (var i = 1; i <= 6; i++) {
      final value = int.tryParse(match.group(i) ?? '');
      if (value == null || value < 0 || value > 255) return null;
      parts.add(value);
    }
    final port = parts[4] * 256 + parts[5];
    if (port < 1 || port > 65535) return null;
    return (host: '${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}', port: port);
  }

  /// Parses a `229 Entering Extended Passive Mode (|||6446|)` answer.
  static int? parseExtendedPassiveReply(String message) {
    final match = RegExp(r'\((.)\1\1(\d{1,5})\1\)').firstMatch(message);
    if (match == null) return null;
    final port = int.tryParse(match.group(2) ?? '');
    if (port == null || port < 1 || port > 65535) return null;
    return port;
  }

  /// Parses an `MDTM` timestamp (`213 20240131154500`), interpreted as UTC.
  static DateTime? parseModifiedTime(String message) {
    final match = RegExp(r'(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})')
        .firstMatch(message);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6)!);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 60) return null;
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  static RemoteEntry? _parseDos(String line, String parentPath) {
    final match = _dos.firstMatch(line);
    if (match == null) return null;
    final month = int.tryParse(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final meridiem = match.group(6)?.toUpperCase();
    final sizeToken = match.group(7)!;
    final name = match.group(8)!.trim();
    if (month == null ||
        day == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    if (month < 1 || month > 12) return null;
    if (year < 100) year += 2000;
    var normalizedHour = hour;
    if (meridiem == 'PM' && hour < 12) normalizedHour = hour + 12;
    if (meridiem == 'AM' && hour == 12) normalizedHour = 0;
    if (normalizedHour > 23 || minute > 59) return null;
    final isDirectory = sizeToken.toUpperCase() == '<DIR>';
    final size = isDirectory ? null : int.tryParse(sizeToken);
    return RemoteEntry(
      path: _join(parentPath, name),
      name: name,
      isDirectory: isDirectory,
      sizeBytes: size,
      modifiedAt: DateTime(year, month, day, normalizedHour, minute),
    );
  }

  static RemoteEntry? _parseUnix(String line, String parentPath, DateTime now) {
    final match = _unixWithGroup.firstMatch(line) ??
        _unixWithoutGroup.firstMatch(line);
    if (match == null) return null;
    final typeChar = match.group(1)!.toLowerCase();
    final size = int.tryParse(match.group(2)!);
    final monthToken = match.group(3)!.toLowerCase();
    final day = int.tryParse(match.group(4)!);
    final timeOrYear = match.group(5)!;
    var name = match.group(6)!.trim();
    final monthIndex = _months.indexOf(monthToken);
    if (monthIndex == -1 || day == null) return null;
    if (day < 1 || day > 31) return null;
    final isLink = typeChar == 'l';
    if (isLink) {
      // `name -> target`: only the link name is a browsable entry.
      final arrow = name.indexOf(' -> ');
      if (arrow != -1) name = name.substring(0, arrow).trim();
    }
    if (name.isEmpty || name == '.' || name == '..') return null;
    DateTime? modified;
    if (timeOrYear.contains(':')) {
      final parts = timeOrYear.split(':');
      final hour = int.tryParse(parts.first);
      final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (hour != null && minute != null && hour < 24 && minute < 60) {
        var year = now.year;
        var candidate = DateTime(year, monthIndex + 1, day, hour, minute);
        // A timestamp later than "now" means the listing refers to last year.
        if (candidate.difference(now) > const Duration(days: 1)) {
          year -= 1;
          candidate = DateTime(year, monthIndex + 1, day, hour, minute);
        }
        modified = candidate;
      }
    } else {
      final year = int.tryParse(timeOrYear);
      if (year != null) modified = DateTime(year, monthIndex + 1, day);
    }
    return RemoteEntry(
      path: _join(parentPath, name),
      name: name,
      isDirectory: typeChar == 'd',
      sizeBytes: typeChar == 'd' ? null : size,
      modifiedAt: modified,
    );
  }

  static String _join(String parentPath, String name) {
    var parent = parentPath.trim();
    while (parent.startsWith('/')) {
      parent = parent.substring(1);
    }
    while (parent.endsWith('/')) {
      parent = parent.substring(0, parent.length - 1);
    }
    return parent.isEmpty ? name : '$parent/$name';
  }
}
