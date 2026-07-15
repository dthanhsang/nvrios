import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom DVR Client',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF2F4F7),
        primaryColor: const Color(0xFFFF3B30),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF3B30),
          secondary: Color(0xFFFF3B30),
          surface: Color(0xFFFFFFFF),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF1E293B),
        ),
        cardColor: const Color(0xFFFFFFFF),
        cardTheme: CardTheme(
          color: const Color(0xFFFFFFFF),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF1E293B),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          selectedItemColor: Color(0xFFFF3B30),
          unselectedItemColor: Color(0xFF64748B),
        ),
        dividerColor: const Color(0xFFE2E8F0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          labelStyle: const TextStyle(color: Color(0xFF64748B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFF3B30))),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF1E293B)),
          bodyMedium: TextStyle(color: Color(0xFF1E293B)),
          bodySmall: TextStyle(color: Color(0xFF64748B)),
          titleLarge: TextStyle(color: Color(0xFF1E293B)),
          titleMedium: TextStyle(color: Color(0xFF1E293B)),
          titleSmall: TextStyle(color: Color(0xFF64748B)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFFF3B30),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? const Color(0xFFFF3B30) : const Color(0xFF7E8B9B)),
          trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? const Color(0xFFFF3B30).withOpacity(0.5) : const Color(0xFFE2E8F0)),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFFFF3B30),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF3B30),
          secondary: Color(0xFFFF3B30),
          surface: Color(0xFF161920),
          onPrimary: Color(0xFFE2E8F0),
          onSecondary: Color(0xFFE2E8F0),
          onSurface: Color(0xFFE2E8F0),
        ),
        cardColor: const Color(0xFF161920),
        cardTheme: CardTheme(
          color: const Color(0xFF161920),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161920),
          foregroundColor: Color(0xFFE2E8F0),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF161920),
          selectedItemColor: Color(0xFFFF3B30),
          unselectedItemColor: Color(0xFF7E8B9B),
        ),
        dividerColor: const Color(0xFF2A2F3A),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2330),
          labelStyle: const TextStyle(color: Color(0xFF7E8B9B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2A2F3A))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2A2F3A))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFF3B30))),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFE2E8F0)),
          bodyMedium: TextStyle(color: Color(0xFFE2E8F0)),
          bodySmall: TextStyle(color: Color(0xFF7E8B9B)),
          titleLarge: TextStyle(color: Color(0xFFE2E8F0)),
          titleMedium: TextStyle(color: Color(0xFFE2E8F0)),
          titleSmall: TextStyle(color: Color(0xFF7E8B9B)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFFFF3B30),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? const Color(0xFFFF3B30) : const Color(0xFF7E8B9B)),
          trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? const Color(0xFFFF3B30).withOpacity(0.5) : const Color(0xFF2A2F3A)),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
