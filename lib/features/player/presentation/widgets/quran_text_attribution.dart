import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_dialog.dart';
import '../../../../data/quran/quran_uthmani_text.dart';

/// Source attribution stays available offline alongside the scripture.
class QuranTextAttribution extends StatelessWidget {
  const QuranTextAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      child: const Text('Tanzil Project · tanzil.net'),
      onPressed: () => PulsrDialogHelper.showPulsrDialog<void>(
        context,
        title: const Text('Tanzil Quran Text · Uthmani 1.1'),
        content: const SingleChildScrollView(
          child: SelectableText(tanzilCopyrightNotice),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await InAppBrowser.openWithSystemBrowser(
                  url: WebUri('https://tanzil.net/'),
                );
              } catch (_) {
                // The source remains selectable when no browser is available.
              }
            },
            child: const Text('https://tanzil.net/'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }
}
