import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickerswap/models/curated_pack.dart';
import 'package:stickerswap/screens/home_screen.dart';
import 'package:stickerswap/widgets/curated_packs_carousel.dart';

void main() {
  testWidgets('CuratedPacksCarousel filters categories and notifies selection',
      (tester) async {
    CuratedPack? tappedPack;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CuratedPacksCarousel(
            onPackSelected: (pack) => tappedPack = pack,
          ),
        ),
      ),
    );

    expect(find.text('Popüler ve Trend Paketler'), findsOneWidget);
    expect(find.text('Pepe The Frog'), findsOneWidget);

    await tester.tap(find.text('Oyun'));
    await tester.pumpAndSettle();

    expect(find.text('Pepe The Frog'), findsNothing);
    expect(find.text('Among Us Karakterleri'), findsOneWidget);

    await tester.tap(find.text('Among Us Karakterleri'));
    await tester.pump();

    expect(tappedPack?.name, 'AmongUsStickers');
  });

  testWidgets('HomeScreen displays curated carousel and fills search on card tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Popüler ve Trend Paketler'), findsOneWidget);
    expect(find.text('Pepe The Frog'), findsOneWidget);

    await tester.ensureVisible(find.text('Pepe The Frog'));
    await tester.pump();
    await tester.tap(find.text('Pepe The Frog'));
    await tester.pump(const Duration(milliseconds: 200));

    final editable = tester.widget<TextField>(find.byType(TextField).first);
    expect(editable.controller?.text, 'PepeTheKing');
  });
}
