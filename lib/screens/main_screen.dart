import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'live_screen.dart';
import 'playback_screen.dart';
import 'events_screen.dart';
import 'config_screen.dart';
import 'health_screen.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _apiService = ApiService();
  int _currentIndex = 0;
  DateTime? _lastLiveTap;

  final List<Widget> _screens = const [
    LiveScreen(),
    PlaybackScreen(),
    EventsScreen(),
    ConfigScreen(),
    HealthScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _apiService.setOnSessionExpired(_handleSessionExpired);
  }

  void _handleSessionExpired() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phiên đăng nhập đã hết hạn')),
    );
  }

  void _onTabTapped(int index) {
    if (index == 0 && _currentIndex == 0) {
      final now = DateTime.now();
      if (_lastLiveTap != null && now.difference(_lastLiveTap!) < const Duration(milliseconds: 500)) {
        _showAppMenu();
        _lastLiveTap = null;
        return;
      }
      _lastLiveTap = now;
    }
    setState(() => _currentIndex = index);
  }

  void _showAppMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2330),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.videocam_rounded, color: Color(0xFFFF3B30), size: 36),
            const SizedBox(height: 8),
            const Text('WebDVR Flutter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('Phiên bản 2.0.0', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(_apiService.baseUrl, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFFF3B30)),
              title: const Text('Đăng xuất', style: TextStyle(color: Color(0xFFFF3B30))),
              onTap: () {
                Navigator.pop(ctx);
                _confirmLogout();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2330),
        title: const Text('Đăng xuất', style: TextStyle(color: Colors.white)),
        content: const Text('Bạn có chắc muốn đăng xuất?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _apiService.logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Đăng xuất', style: TextStyle(color: Color(0xFFFF3B30))),
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
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: 'Trực tiếp'),
          BottomNavigationBarItem(icon: Icon(Icons.replay), label: 'Xem lại'),
          BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Sự kiện'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cấu hình'),
          BottomNavigationBarItem(icon: Icon(Icons.monitor_heart), label: 'Hệ thống'),
        ],
      ),
    );
  }
}
