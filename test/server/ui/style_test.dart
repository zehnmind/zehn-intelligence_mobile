import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/ui/launcher_button.dart';
import 'package:zehn_intelligence/src/server/ui/soap_bubble.dart';
import 'package:zehn_intelligence/src/server/ui/style.dart';

void main() {
  test('defaults match the design palette', () {
    const s = ZiChatStyle();
    expect(s.background, const Color(0xFFFFFFFF));
    expect(s.ink, const Color(0xE61D1D16));
    expect(s.muted, const Color(0x991D1D16));
    expect(s.line, const Color(0x1A1D1D16));
    expect(s.fill, const Color(0x0D1D1D16));
    expect(s.accent, const Color(0xFFBE7C6C));
    expect(s.barrier, const Color(0x9919212F));
  });

  test('accent and font come from the console theme', () {
    final s = ZiChatStyle.fromTheme({
      'font': 'CeraPro',
      'colors': {'accent': '#FF2266DD', 'on_accent': '#FF000000'},
    });
    expect(s.accent, const Color(0xFF2266DD));
    expect(s.onAccent, const Color(0xFF000000));
    expect(s.title.fontFamily, 'CeraPro');
    expect(s.title.fontSize, 20);
    expect(s.body.fontSize, 17);
    expect(s.small.fontSize, 15);
  });

  testWidgets('a soap bubble with reduced motion is still and tappable', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Center(child: SoapBubble(size: 128, onTap: () => taps++))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SoapBubble));
    expect(taps, 1);
  });

  testWidgets('the launcher calls onTap', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Center(child: ZiLauncherButton(onTap: () => taps++))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ZiLauncherButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
