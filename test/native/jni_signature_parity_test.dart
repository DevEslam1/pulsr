import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _JniSignature {
  const _JniSignature({
    required this.symbol,
    required this.returnType,
    required this.paramTypes,
    required this.sourceLocation,
  });

  final String symbol;
  final String returnType;
  final List<String> paramTypes;
  final String sourceLocation;

  String describe() => '$returnType $symbol(${paramTypes.join(', ')})';
}

String _jniMangle(String identifier) => identifier.replaceAll('_', '_1');

String _buildJniSymbol(String pkg, String className, String methodName) {
  final pkgPart = pkg.split('.').map(_jniMangle).join('_');
  return 'Java_${pkgPart}_${_jniMangle(className)}_${_jniMangle(methodName)}';
}

String _mapKotlinTypeToJni(String rawType) {
  final t = rawType.replaceAll('?', '').trim();
  switch (t) {
    case '':
    case 'Unit':
      return 'void';
    case 'Boolean':
      return 'jboolean';
    case 'Byte':
      return 'jbyte';
    case 'Short':
      return 'jshort';
    case 'Int':
      return 'jint';
    case 'Long':
      return 'jlong';
    case 'Float':
      return 'jfloat';
    case 'Double':
      return 'jdouble';
    case 'String':
      return 'jstring';
    case 'BooleanArray':
      return 'jbooleanArray';
    case 'ByteArray':
      return 'jbyteArray';
    case 'ShortArray':
      return 'jshortArray';
    case 'IntArray':
      return 'jintArray';
    case 'LongArray':
      return 'jlongArray';
    case 'FloatArray':
      return 'jfloatArray';
    case 'DoubleArray':
      return 'jdoubleArray';
    case 'ByteBuffer':
    case 'Any':
      return 'jobject';
    default:
      if (t.startsWith('Array<')) return 'jobjectArray';
      return 'jobject:$t';
  }
}

String _mapJavaTypeToJni(String rawType) {
  final normalized = rawType
      .replaceAll(RegExp(r'@\w+\s*'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
  switch (normalized) {
    case 'void':
      return 'void';
    case 'boolean':
      return 'jboolean';
    case 'byte':
      return 'jbyte';
    case 'short':
      return 'jshort';
    case 'int':
      return 'jint';
    case 'long':
      return 'jlong';
    case 'float':
      return 'jfloat';
    case 'double':
      return 'jdouble';
    case 'String':
      return 'jstring';
    case 'boolean[]':
      return 'jbooleanArray';
    case 'byte[]':
      return 'jbyteArray';
    case 'short[]':
      return 'jshortArray';
    case 'int[]':
      return 'jintArray';
    case 'long[]':
      return 'jlongArray';
    case 'float[]':
      return 'jfloatArray';
    case 'double[]':
      return 'jdoubleArray';
    case 'ByteBuffer':
    case 'Object':
      return 'jobject';
    default:
      if (normalized.endsWith('[]')) return 'jobjectArray';
      return 'jobject:$normalized';
  }
}

String _stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      i += 2;
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      out.write(' ');
      continue;
    }
    if (c == '"' || c == '\'') {
      final quote = c;
      out.write(quote);
      i++;
      while (i < source.length) {
        final sc = source[i];
        if (sc == '\\' && i + 1 < source.length) {
          i += 2;
          continue;
        }
        if (sc == quote) {
          i++;
          break;
        }
        if (sc == '\n') out.write('\n');
        i++;
      }
      out.write(quote);
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

String? _enclosingTypeAtOffset(String clean, int offset,
    {required bool isKotlin}) {
  final typeDeclPattern = isKotlin
      ? RegExp(
          r'\b(?:companion\s+object|(?:(?:data|inner|enum|sealed|open|abstract|private|internal|public|final|annotation|value)\s+)*(?:class|object))\s*([A-Za-z_]\w*)?')
      : RegExp(
          r'\b(?:(?:public|private|protected|static|final|abstract|strictfp)\s+)*(?:class|interface|enum)\s+([A-Za-z_]\w*)');

  final events = <({int index, String kind, String? name})>[];
  for (final m in typeDeclPattern.allMatches(clean)) {
    if (m.start >= offset) break;
    final text = clean.substring(m.start, m.end);
    if (text.contains(RegExp(r'\bcompanion\s+object\b'))) {
      events.add((index: m.start, kind: 'companion', name: null));
    } else if (m.group(1) != null) {
      events.add((index: m.start, kind: 'type', name: m.group(1)!));
    }
  }

  final stack = <String?>[];
  String? pendingType;
  var eventIdx = 0;
  var parenDepth = 0;

  for (var i = 0; i < offset; i++) {
    while (eventIdx < events.length && events[eventIdx].index == i) {
      final ev = events[eventIdx++];
      if (parenDepth == 0) {
        pendingType = ev.kind == 'companion' ? '__COMPANION__' : ev.name;
      }
    }
    final ch = clean[i];
    if (ch == '(') {
      parenDepth++;
    } else if (ch == ')' && parenDepth > 0) {
      parenDepth--;
    } else if (ch == '{') {
      if (pendingType == '__COMPANION__') {
        stack.add(stack.isNotEmpty ? stack.last : null);
      } else {
        stack.add(pendingType ?? (stack.isNotEmpty ? stack.last : null));
      }
      pendingType = null;
    } else if (ch == ';') {
      if (parenDepth == 0) pendingType = null;
    } else if (ch == '}' && stack.isNotEmpty) {
      stack.removeLast();
      pendingType = null;
    }
  }
  for (var j = stack.length - 1; j >= 0; j--) {
    if (stack[j] != null) return stack[j];
  }
  return null;
}

List<_JniSignature> _parseKotlinNatives(File file) {
  final clean = _stripCommentsAndStrings(file.readAsStringSync());
  final pkgMatch = RegExp(r'^\s*package\s+([A-Za-z0-9_.]+)', multiLine: true)
      .firstMatch(clean);
  if (pkgMatch == null) return const [];
  final pkg = pkgMatch.group(1)!;

  final sigs = <_JniSignature>[];
  final declPattern = RegExp(
    r'\bexternal\s+fun\s+([A-Za-z_]\w*)\s*\(([^)]*)\)(?:\s*:\s*([A-Za-z0-9_<>?]+))?',
    multiLine: true,
    dotAll: true,
  );
  for (final m in declPattern.allMatches(clean)) {
    final className = _enclosingTypeAtOffset(clean, m.start, isKotlin: true);
    if (className == null) {
      throw FormatException(
          'No enclosing class for Kotlin external fun ${m.group(1)} in ${file.path}');
    }
    final method = m.group(1)!;
    final rawParams = m.group(2)!.trim();
    final rawRet = (m.group(3) ?? 'Unit').trim();
    final paramTypes = <String>[];
    if (rawParams.isNotEmpty) {
      for (final param in rawParams.split(',')) {
        final p = param.trim();
        if (p.isEmpty) continue;
        final colonIdx = p.indexOf(':');
        if (colonIdx < 0) {
          throw FormatException('Unparsed Kotlin param "$p" in ${file.path}');
        }
        var typePart = p.substring(colonIdx + 1).trim();
        final eqIdx = typePart.indexOf('=');
        if (eqIdx >= 0) {
          typePart = typePart.substring(0, eqIdx).trim();
        }
        paramTypes.add(_mapKotlinTypeToJni(typePart));
      }
    }
    sigs.add(
      _JniSignature(
        symbol: _buildJniSymbol(pkg, className, method),
        returnType: _mapKotlinTypeToJni(rawRet),
        paramTypes: paramTypes,
        sourceLocation: file.path,
      ),
    );
  }
  return sigs;
}

List<_JniSignature> _parseJavaNatives(File file) {
  final clean = _stripCommentsAndStrings(file.readAsStringSync());
  final pkgMatch =
      RegExp(r'^\s*package\s+([A-Za-z0-9_.]+)\s*;', multiLine: true)
          .firstMatch(clean);
  if (pkgMatch == null) return const [];
  final pkg = pkgMatch.group(1)!;

  final sigs = <_JniSignature>[];
  final declPattern = RegExp(
    r'(?:^|\n|\})\s*(?:(?:public|private|protected|static|final|synchronized|strictfp)\s+)*native\s+([A-Za-z0-9_.<>\[\]]+)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*;',
    multiLine: true,
    dotAll: true,
  );
  for (final m in declPattern.allMatches(clean)) {
    final className = _enclosingTypeAtOffset(clean, m.start, isKotlin: false);
    if (className == null) {
      throw FormatException(
          'No enclosing class for Java native ${m.group(2)} in ${file.path}');
    }
    final rawRet = m.group(1)!.trim();
    final method = m.group(2)!.trim();
    final rawParams = m.group(3)!.trim();
    final paramTypes = <String>[];
    if (rawParams.isNotEmpty) {
      for (final param in rawParams.split(',')) {
        final tokens = param
            .trim()
            .replaceAll(RegExp(r'\s*\[\s*\]'), '[]')
            .split(RegExp(r'\s+'));
        if (tokens.length < 2) {
          throw FormatException('Unparsed Java param "$param" in ${file.path}');
        }
        // Handle `final Type name`
        final typeToken =
            tokens.first == 'final' ? tokens[1] : tokens[tokens.length - 2];
        paramTypes.add(_mapJavaTypeToJni(typeToken));
      }
    }
    sigs.add(
      _JniSignature(
        symbol: _buildJniSymbol(pkg, className, method),
        returnType: _mapJavaTypeToJni(rawRet),
        paramTypes: paramTypes,
        sourceLocation: file.path,
      ),
    );
  }
  return sigs;
}

String _normalizeCppJniType(String rawType) {
  final t = rawType.replaceAll(RegExp(r'\bconst\b'), '').trim();
  if (t == 'jclass') return 'jobject';
  return t;
}

List<_JniSignature> _parseCppExports(File file) {
  final clean = _stripCommentsAndStrings(file.readAsStringSync());
  final sigs = <_JniSignature>[];
  final exportPattern = RegExp(
    r'JNIEXPORT\s+([A-Za-z_]\w*)\s+JNICALL\s+(Java_[A-Za-z0-9_]+)\s*\(([^)]*)\)',
    multiLine: true,
    dotAll: true,
  );
  for (final m in exportPattern.allMatches(clean)) {
    final retType = _normalizeCppJniType(m.group(1)!);
    final symbol = m.group(2)!.trim();
    final rawParams = m.group(3)!.trim();
    final parts = rawParams
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    // First two parameters of every JNI function are JNIEnv* and jobject/jclass.
    if (parts.length < 2 || !parts[0].contains('JNIEnv')) {
      throw FormatException(
          'Unexpected JNI prologue for $symbol in ${file.path}: $rawParams');
    }
    final userParams = <String>[];
    for (final param in parts.skip(2)) {
      final typeMatch =
          RegExp(r'^\s*(?:const\s+)?([A-Za-z_]\w*)').firstMatch(param);
      if (typeMatch == null) {
        throw FormatException('Unparsed C++ JNI param "$param" for $symbol');
      }
      userParams.add(_normalizeCppJniType(typeMatch.group(1)!));
    }
    sigs.add(
      _JniSignature(
        symbol: symbol,
        returnType: retType,
        paramTypes: userParams,
        sourceLocation: file.path,
      ),
    );
  }
  return sigs;
}

List<File> _collectFiles(String dirPath, String extension) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(extension))
      .toList();
}

void main() {
  test(
      'All C++ JNIEXPORT symbols match Java/Kotlin native declarations with exact signatures',
      () {
    final cppFiles = _collectFiles('android/app/src/main/cpp', '.cpp');
    final ktFiles = _collectFiles('android/app/src/main/kotlin', '.kt');
    final javaFiles = [
      ..._collectFiles('android/app/src/main/java', '.java'),
      ..._collectFiles('third_party/just_audio/android/src/main/java', '.java'),
    ];

    expect(cppFiles, isNotEmpty);
    expect(ktFiles, isNotEmpty);
    expect(javaFiles, isNotEmpty);

    final cppMap = <String, _JniSignature>{};
    final duplicateCpp = <String>[];
    for (final file in cppFiles) {
      for (final sig in _parseCppExports(file)) {
        if (cppMap.containsKey(sig.symbol)) {
          duplicateCpp.add('${sig.symbol} (${file.path})');
        }
        cppMap[sig.symbol] = sig;
      }
    }
    expect(duplicateCpp, isEmpty,
        reason: 'Duplicate C++ JNIEXPORT symbols found: $duplicateCpp');

    final managedMap = <String, _JniSignature>{};
    final duplicateManaged = <String>[];
    for (final file in ktFiles) {
      for (final sig in _parseKotlinNatives(file)) {
        if (managedMap.containsKey(sig.symbol)) {
          duplicateManaged.add('${sig.symbol} (${file.path})');
        }
        managedMap[sig.symbol] = sig;
      }
    }
    for (final file in javaFiles) {
      for (final sig in _parseJavaNatives(file)) {
        if (managedMap.containsKey(sig.symbol)) {
          duplicateManaged.add('${sig.symbol} (${file.path})');
        }
        managedMap[sig.symbol] = sig;
      }
    }
    expect(
      duplicateManaged,
      isEmpty,
      reason:
          'Duplicate or overloaded Java/Kotlin native declarations found: $duplicateManaged',
    );
    expect(managedMap.length, greaterThan(50));

    final orphanCpp = cppMap.keys
        .where((sym) => !managedMap.containsKey(sym))
        .toList()
      ..sort();
    final missingCpp = managedMap.keys
        .where((sym) => !cppMap.containsKey(sym))
        .toList()
      ..sort();

    expect(
      orphanCpp,
      isEmpty,
      reason:
          'Orphan C++ JNIEXPORT functions with no Kotlin/Java declaration: $orphanCpp',
    );
    expect(
      missingCpp,
      isEmpty,
      reason:
          'Kotlin/Java native methods missing C++ JNIEXPORT implementation: $missingCpp',
    );

    final mismatches = <String>[];
    for (final entry in managedMap.entries) {
      final managed = entry.value;
      final cpp = cppMap[entry.key]!;
      if (managed.returnType != cpp.returnType ||
          managed.paramTypes.length != cpp.paramTypes.length) {
        mismatches.add(
          '${entry.key}: managed=${managed.describe()} vs cpp=${cpp.describe()}',
        );
        continue;
      }
      for (var i = 0; i < managed.paramTypes.length; i++) {
        if (managed.paramTypes[i] != cpp.paramTypes[i]) {
          mismatches.add(
            '${entry.key} param#$i: managed=${managed.describe()} vs cpp=${cpp.describe()}',
          );
        }
      }
    }
    expect(mismatches, isEmpty,
        reason:
            'JNI parameter/return type mismatches:\n${mismatches.join('\n')}');

    // Explicit H-02 & L-03 regression assertions.
    final isUsbExclusive = cppMap[
        'Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeIsUsbExclusive'];
    expect(isUsbExclusive, isNotNull);
    expect(isUsbExclusive!.returnType, 'jboolean');
    expect(isUsbExclusive.paramTypes, ['jlong']);

    const removedLegacyExports = [
      'Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerRates',
      'Java_com_pulsr_music_AudioEffectsPlugin_nativeSetSincResamplerQuality',
      'Java_com_pulsr_music_AudioEffectsPlugin_nativeSetDirectUsbActive',
      'Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeWasLastBlockBitPerfect',
      'Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeWasSafetySuppressed',
      'Java_com_ryanheise_just_1audio_NativeDspAudioProcessor_nativeSetDirectUsbActive',
    ];
    for (final legacy in removedLegacyExports) {
      expect(cppMap.containsKey(legacy), isFalse,
          reason: '$legacy should remain deleted');
    }
  });
}
