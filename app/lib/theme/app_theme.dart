import 'package:material_ui/material_ui.dart';

/// Controller leggero per alternare tra tema chiaro (Indaco & Grafite)
/// e tema scuro (Notte & Ambra) senza dipendenze esterne.
class AppThemeController extends ValueNotifier<ThemeMode> {
  AppThemeController([super.value = ThemeMode.system]);

  void toggle(Brightness currentBrightness) {
    value = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }
}

final AppThemeController appThemeController = AppThemeController();

/// Palette WCAG AA+ condivise tra Flutter PWA e Console Admin (`/admin`).
/// - Light: Indaco & Grafite (`#3B5BDB` su `#FFFFFF`, contrasto 5.67:1)
/// - Dark: Notte & Ambra (`#E07A3F` con testo `#11161D`, contrasto 6.11:1)
class AppTheme {
  const AppTheme._();

  // ---- Light: Indaco & Grafite ----
  static const Color lightInk = Color(0xFF151B2E);
  static const Color lightInkSoft = Color(0xFF4C5772);
  static const Color lightPaper = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFF8F9FC);
  static const Color lightBorder = Color(0xFFDCE1EC);
  static const Color lightAccent = Color(0xFF3B5BDB);
  static const Color lightAccentSoft = Color(0xFFE8EEFF);
  static const Color lightAccentSoftFg = Color(0xFF2B48BF);
  static const Color lightOk = Color(0xFF127A4E);
  static const Color lightError = Color(0xFFC92A2A);

  // ---- Dark: Notte & Ambra ----
  static const Color darkInk = Color(0xFFF1F5F9);
  static const Color darkInkSoft = Color(0xFF9FB0C3);
  static const Color darkPaper = Color(0xFF11161D);
  static const Color darkSurface = Color(0xFF19212B);
  static const Color darkSurfaceMuted = Color(0xFF222C38);
  static const Color darkBorder = Color(0xFF2E3B4A);
  static const Color darkAccent = Color(0xFFE07A3F);
  static const Color darkAccentFg = Color(0xFF11161D);
  static const Color darkAccentSoft = Color(0xFF332219);
  static const Color darkAccentSoftFg = Color(0xFFF6B187);
  static const Color darkOk = Color(0xFF34D399);
  static const Color darkError = Color(0xFFF87171);

  static Color successColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkOk : lightOk;

  static ThemeData get light {
    const ColorScheme scheme = ColorScheme.light(
      primary: lightAccent,
      onPrimary: Colors.white,
      primaryContainer: lightAccentSoft,
      onPrimaryContainer: lightAccentSoftFg,
      secondary: lightInk,
      onSecondary: Colors.white,
      secondaryContainer: lightSurfaceMuted,
      onSecondaryContainer: lightInk,
      surface: lightSurface,
      onSurface: lightInk,
      onSurfaceVariant: lightInkSoft,
      surfaceContainerLowest: lightSurface,
      surfaceContainerLow: lightSurfaceMuted,
      surfaceContainer: lightSurfaceMuted,
      surfaceContainerHigh: lightAccentSoft,
      surfaceContainerHighest: lightBorder,
      outline: lightBorder,
      outlineVariant: lightBorder,
      error: lightError,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightPaper,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: lightPaper,
        foregroundColor: lightInk,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: lightSurface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: lightBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: lightAccent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lightAccent,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: lightAccent, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightSurface,
        selectedColor: lightAccentSoft,
        side: const BorderSide(color: lightBorder),
        labelStyle: const TextStyle(color: lightInk),
        secondaryLabelStyle: const TextStyle(
          color: lightAccentSoftFg,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: lightInk,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }

  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: darkAccent,
      onPrimary: darkAccentFg,
      primaryContainer: darkAccentSoft,
      onPrimaryContainer: darkAccentSoftFg,
      secondary: darkInk,
      onSecondary: darkPaper,
      secondaryContainer: darkSurfaceMuted,
      onSecondaryContainer: darkInk,
      surface: darkSurface,
      onSurface: darkInk,
      onSurfaceVariant: darkInkSoft,
      surfaceContainerLowest: darkPaper,
      surfaceContainerLow: darkSurface,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkSurfaceMuted,
      surfaceContainerHighest: darkBorder,
      outline: darkBorder,
      outlineVariant: darkBorder,
      error: darkError,
      onError: darkPaper,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkPaper,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: darkPaper,
        foregroundColor: darkInk,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: darkSurface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: darkBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: darkAccentFg,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkAccent,
        foregroundColor: darkAccentFg,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: darkAccent, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurface,
        selectedColor: darkAccentSoft,
        side: const BorderSide(color: darkBorder),
        labelStyle: const TextStyle(color: darkInk),
        secondaryLabelStyle: const TextStyle(
          color: darkAccentSoftFg,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: darkSurfaceMuted,
        contentTextStyle: TextStyle(color: darkInk),
      ),
    );
  }
}

/// Pulsante accessibile per cambiare al volo tra Light (Indaco & Grafite)
/// e Dark (Notte & Ambra).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.controller});

  final AppThemeController? controller;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final AppThemeController activeController =
        controller ?? appThemeController;
    return IconButton(
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      tooltip: isDark
          ? 'Passa al tema chiaro (Indaco)'
          : 'Passa al tema scuro (Notte e Ambra)',
      onPressed: () => activeController.toggle(Theme.of(context).brightness),
    );
  }
}
