// test/features/player/widgets/hrtf_binaural_card_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/hrtf_binaural_card.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockCubit;

  setUp(() {
    mockCubit = MockPlayerCubit();
    when(() => mockCubit.state).thenReturn(
      const PlayerState(
        dsp: DspSlice(
          isCrossfeedEnabled: false,
        ),
      ),
    );
    when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildCard({
    String? blockedReason,
    bool nativeAvailable = true,
  }) {
    return MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlocProvider<PlayerCubit>.value(
            value: mockCubit,
            child: HrtfBinauralCard(
              blockedReason: blockedReason,
              nativeAvailable: nativeAvailable,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('HrtfBinauralCard renders default off state', (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    expect(find.text('HRTF 3D Binaural Spatializer'), findsOneWidget);
    expect(find.text('Partitioned SOFA/HRIR convolution for 3D realism'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Virtual Speaker Azimuth'), findsNothing);
  });

  testWidgets('Toggling HRTF on reveals Azimuth and Elevation controls', (tester) async {
    when(() => mockCubit.setHrtfBinaural(
          any(),
          azimuth: any(named: 'azimuth'),
          elevation: any(named: 'elevation'),
          sofaPath: any(named: 'sofaPath'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Virtual Speaker Azimuth'), findsOneWidget);
    expect(find.text('Virtual Speaker Elevation'), findsOneWidget);
    expect(find.text('Load Custom SOFA / WAV...'), findsOneWidget);

    verify(() => mockCubit.setHrtfBinaural(
          true,
          azimuth: any(named: 'azimuth'),
          elevation: any(named: 'elevation'),
          sofaPath: any(named: 'sofaPath'),
        )).called(1);
  });

  testWidgets('Shows blocked by bit-perfect message when blockedReason is provided', (tester) async {
    await tester.pumpWidget(buildCard(blockedReason: 'Bit-perfect direct stream active'));
    await tester.pumpAndSettle();

    expect(find.text('Blocked by Bit-Perfect (Bit-perfect direct stream active)'), findsOneWidget);
  });

  testWidgets('Warns about mutual exclusivity when Crossfeed is active', (tester) async {
    when(() => mockCubit.state).thenReturn(
      const PlayerState(
        dsp: DspSlice(
          isCrossfeedEnabled: true,
        ),
      ),
    );
    when(() => mockCubit.setHrtfBinaural(
          any(),
          azimuth: any(named: 'azimuth'),
          elevation: any(named: 'elevation'),
          sofaPath: any(named: 'sofaPath'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Mutually exclusive: Engaging HRTF disables Headphone Crossfeed.'), findsOneWidget);
  });
}
