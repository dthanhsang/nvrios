import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'live_screen.dart';
import 'playback_screen.dart';
import 'config_screen.dart';
import 'events_screen.dart';
import 'health_screen.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _apiService = ApiService();

  final List<Widget> _pages = const [
    LiveScreen(),
    PlaybackScreen(),
    EventsScreen(),
    ConfigScreen(),
    HealthScreen(),
  ];

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161920),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3E4556),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // App info
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.security, color: Color(0xFFFF3B30), size: 32),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("WebDVR Flutter",
                        style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Phiên bản 2.0.0",
                        style: TextStyle(color: Color(0xFF7E8B9B), fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF232731)),
            // Server info
            ListTile(
              leading: const Icon(Icons.dns, color: Color(0xFF7E8B9B)),
              title: const Text("Máy chủ", style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 14)),
              subtitle: Text(_apiService.baseUrl,
                style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 12)),
            ),
            const Divider(color: Color(0xFF232731)),
            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFFF3B30)),
              title: const Text("Đăng xuất",
                style: TextStyle(color: Color(0xFFFF3B30), fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () => _handleLogout(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _handleLogout(BuildContext sheetContext) {
    showDialog(
      context: sheetContext,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161920),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Đăng xuất", style: TextStyle(color: Color(0xFFE2E8F0))),
        content: const Text("Bạn có muốn đăng xuất khỏi hệ thống?",
          style: TextStyle(color: Color(0xFF7E8B9B))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy", style: TextStyle(color: Color(0xFF7E8B9B))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              Navigator.pop(sheetContext); // close bottom sheet
              await _apiService.logout();
              if (mounted) {
                Navigator.of(this.context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
            child: const Text("Đăng xuất"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF232731), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index == _currentIndex && index == 0) {
              // Double-tap Live tab = show menu
              _showMenu();
            } else {
              setState(() => _currentIndex = index);
            }
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFF3B30),
          unselectedItemColor: const Color(0xFF7E8B9B),
          backgroundColor: const Color(0xFF161920),
          selectedFontSize: 11,
          unselectedFontSize: 10,
          iconSize: 22,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Trực tiếp"),
            BottomNavigationBarItem(icon: Icon(Icons.slow_motion_video), label: "Xem lại"),
            BottomNavigationBarItem(icon: Icon(Icons.face), label: "Sự kiện"),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Cấu hình"),
            BottomNavigationBarItem(icon: Icon(Icons.monitor_heart), label: "Hệ thống"),
          ],
        ),
      ),
    );
  }
}
