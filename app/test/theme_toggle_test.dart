import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/theme/app_theme.dart';

void main() {
  testWidgets('ThemeToggleButton alterna tra Light (Indaco) e Dark (Notte)',
      (WidgetTester tester) async {
    final AppThemeController controller = AppThemeController(ThemeMode.light);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: controller,
        builder: (BuildContext context, ThemeMode mode, _) {
          return MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Test Tema'),
                actions: <Widget>[
                  ThemeToggleButton(controller: controller),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          );
        },
      ),
    );

    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(controller.value, ThemeMode.light);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(controller.value, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(controller.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  test('Palette Light (Indaco) e Dark (Notte e Ambra) usano i token corretti',
      () {
    expect(AppTheme.light.scaffoldBackgroundColor, AppTheme.lightPaper);
    expect(AppTheme.light.colorScheme.primary, AppTheme.lightAccent);
    expect(AppTheme.dark.scaffoldBackgroundColor, AppTheme.darkPaper);
    expect(AppTheme.dark.colorScheme.primary, AppTheme.darkAccent);
    expect(AppTheme.dark.colorScheme.onPrimary, AppTheme.darkAccentFg);
  });
}
