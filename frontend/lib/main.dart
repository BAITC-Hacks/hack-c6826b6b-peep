import 'package:flutter/material.dart';

import 'core/api.dart';
import 'pages/workspace.dart';
import 'widgets/ui.dart';

void main() => runApp(const CareerQuestApp());

class CareerQuestApp extends StatelessWidget {
  const CareerQuestApp({super.key, this.api});
  final CareerApi? api;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Career Quest',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: violet,
        brightness: Brightness.dark,
        primary: pink,
        onPrimary: night,
        secondary: blue,
        onSecondary: night,
        surface: panel,
        onSurface: ink,
        error: danger,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: panel,
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.5),
        bodyMedium: TextStyle(color: ink, fontSize: 14, height: 1.5),
        bodyLarge: TextStyle(color: ink, height: 1.5),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      dividerColor: line,
      dividerTheme: const DividerThemeData(color: line, thickness: .7),
      iconTheme: const IconThemeData(color: muted),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: pink,
        selectionColor: blue.withValues(alpha: .3),
        selectionHandleColor: pink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111A33),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: blue, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: night,
          backgroundColor: pink,
          disabledBackgroundColor: panelRaised,
          disabledForegroundColor: muted,
          shadowColor: pink.withValues(alpha: .28),
          elevation: 3,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: Color(0xFF8173AF)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelRaised,
        selectedColor: const Color(0xFF393157),
        labelStyle: const TextStyle(color: ink, fontSize: 12),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: line),
        ),
        titleTextStyle: const TextStyle(
          color: ink,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D152D),
        indicatorColor: const Color(0xFF303A65),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? ink : muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? pink : muted,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: pink,
        linearTrackColor: panelRaised,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: panelRaised,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: panelRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: line),
        ),
        textStyle: const TextStyle(color: ink, fontSize: 12),
      ),
    ),
    home: Workspace(api: api),
  );
}
