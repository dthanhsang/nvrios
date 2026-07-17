import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color primaryColor = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebDVR',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: primaryColor,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        fontFamily: 'Roboto',
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'Roboto',
        ),
        cupertinoOverrideTheme: const CupertinoThemeData(
          primaryColor: primaryColor,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Color(0xFF0F1115),
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: 'Roboto', color: Colors.white),
            actionTextStyle: TextStyle(fontFamily: 'Roboto', color: primaryColor),
            navTitleTextStyle: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontWeight: FontWeight.bold),
            navLargeTitleTextStyle: TextStyle(fontFamily: 'Roboto', color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161920),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1E2330),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF161920),
          selectedItemColor: primaryColor,
          unselectedItemColor: Colors.grey,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2330),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2A3040)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryColor),
          ),
          labelStyle: const TextStyle(fontFamily: 'Roboto'),
          hintStyle: const TextStyle(fontFamily: 'Roboto'),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? primaryColor : Colors.grey),
          trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? primaryColor.withOpacity(0.4) : Colors.grey.withOpacity(0.3)),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
