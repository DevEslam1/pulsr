// test/features/assistant/assistant_search_channel_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/assistant/assistant_search_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AssistantSearchChannel.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('pushes rows as title, subtitle and query maps', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    final accepted = await AssistantSearchChannel().updateSuggestions(const [
      AssistantSuggestion(
        title: 'So What',
        subtitle: 'Miles Davis',
        query: 'so what',
      ),
      AssistantSuggestion(title: 'Blue in Green', query: 'blue in green'),
    ]);

    expect(accepted, isTrue);
    expect(captured, isNotNull);
    expect(
      captured!.method,
      AssistantSearchChannel.methodUpdateSuggestions,
    );
    final rows = captured!.arguments as List<dynamic>;
    expect(rows, hasLength(2));
    expect(rows.first, {
      'title': 'So What',
      'subtitle': 'Miles Davis',
      'query': 'so what',
    });
    expect(rows[1], {
      'title': 'Blue in Green',
      'subtitle': '',
      'query': 'blue in green',
    });
  });

  test('drops rows without a query and caps the payload', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    final suggestions = <AssistantSuggestion>[
      const AssistantSuggestion(title: 'Blank', query: '   '),
      for (var index = 0; index < 40; index++)
        AssistantSuggestion(title: 'Song $index', query: 'song $index'),
    ];

    final accepted =
        await AssistantSearchChannel().updateSuggestions(suggestions);

    expect(accepted, isTrue);
    final rows = captured!.arguments as List<dynamic>;
    expect(rows, hasLength(AssistantSearchChannel.maxSuggestions));
    expect(rows.first, containsPair('query', 'song 0'));
  });

  test('clear sends the clear method', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    expect(await AssistantSearchChannel().clear(), isTrue);
    expect(captured!.method, AssistantSearchChannel.methodClear);
  });

  test('returns false when the host rejects the push', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(
      await AssistantSearchChannel().updateSuggestions(const [
        AssistantSuggestion(title: 'So What', query: 'so what'),
      ]),
      isFalse,
    );
  });

  test('returns false when the host has no handler', () async {
    expect(await AssistantSearchChannel().clear(), isFalse);
    expect(
      await AssistantSearchChannel().updateSuggestions(const [
        AssistantSuggestion(title: 'So What', query: 'so what'),
      ]),
      isFalse,
    );
  });
}
