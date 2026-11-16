import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/cast_service.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';
import 'package:pulsr/data/services/usb_exclusive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audio output singletons dispose idempotently', () {
    // App teardown calls each singleton once; a second call (double dispose in
    // tests, hot restart hand-off) must be a no-op instead of throwing on a
    // closed controller.
    UsbExclusiveService().dispose();
    UsbExclusiveService().dispose();
    HiResAudioService().dispose();
    HiResAudioService().dispose();
    CastService().dispose();
    CastService().dispose();
  });
}
