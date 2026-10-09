// test/data/visualizer/fake_file_picker.dart
//
// Test double for the static `FilePicker.pickFile` entry point. The stores
// resolve their file through `FilePickerPlatform.instance`, so installing a
// fake platform is enough to drive import flows deterministically.
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

final class FakePlatformFile extends PlatformFile {
  FakePlatformFile(this.path, {String? name})
      : _name = name ?? path.split(RegExp(r'[/\\]')).last;

  @override
  final String path;

  final String _name;

  @override
  String get name => _name;

  @override
  Uri get uri => Uri.file(path);

  @override
  XFile get xFile => XFile(path);

  @override
  int? lengthSync() => File(path).lengthSync();

  @override
  Future<int> length() => File(path).length();

  @override
  Future<Uint8List> readAsBytes() => File(path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(path).openRead().map(Uint8List.fromList);
}

class FakeFilePickerPlatform extends FilePickerPlatform {
  FakeFilePickerPlatform({this.result, this.error});

  /// Produces the next pick result (null simulates the user cancelling).
  final PlatformFile? Function()? result;

  /// When set, [pickFile] throws this instead of returning.
  final Object? error;

  int pickFileCalls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickFileCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return result?.call();
  }
}
