import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/quran/quran_uthmani_text.dart';

/// Source attribution stays available offline alongside the scripture.
class QuranTextAttribution extends StatelessWidget {
  const QuranTextAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      child: const Text('Tanzil Project · tanzil.net'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      ),
    );
  }
}
