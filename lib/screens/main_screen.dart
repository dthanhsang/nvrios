import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'live_screen.dart';
import 'playback_screen.dart';
import 'events_screen.dart';
import 'config_screen.dart';
import 'health_screen.dart';
import 'login_screen.dart';
import 'analytics_screen.dart';
import 'ai_chat_screen.dart';
import 'discover_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _apiService = ApiService();
  int _currentIndex = 0;
  DateTime? _lastLiveTap;

  bool get _isAdmin => _apiService.userRole == 'admin';

  // Index for the "More" tab's sub-screen, -1 means show the grid
  int _moreSubIndex = -1;

  // Admin "More" menu items
  static const _moreMenuItems = [
    _MoreItem(icon: Icons.bar_chart, label: 'Thống kê', color: Color(0xFF007AFF)),
    _MoreItem(icon: Icons.smart_toy, label: 'AI Chat', color: Color(0xFF5856D6)),
    _MoreItem(icon: Icons.radar, label: 'Tìm camera', color: Color(0xFFFF9500)),
    _MoreItem(icon: Icons.settings, label: 'Cấu hình', color: Color(0xFF8E8E93)),
    _MoreItem(icon: Icons.monitor_heart, label: 'Hệ thống', color: Color(0xFFFF3B30)),
  ];

  Widget _moreSubScreen(int index) {
    switch (index) {
      case 0: return const AnalyticsScreen();
      case 1: return const AiChatScreen();
      case 2: return const DiscoverScreen();
      case 3: return const ConfigScreen();
      case 4: return const HealthScreen();
      default: return const SizedBox.shrink();
    }
  }

  List<Widget> get _allowedScreens {
    if (_isAdmin) {
      return [
        const LiveScreen(),
        const PlaybackScreen(),
        const EventsScreen(),
        // "More" tab — shows a grid or a selected sub-screen
        _moreSubIndex >= 0
          ? _moreSubScreen(_moreSubIndex)
          : _moreGrid(),
      ];
    } else {
      return const [
        LiveScreen(),
        PlaybackScreen(),
        EventsScreen(),
        AiChatScreen(),
      ];
    }
  }

  List<BottomNavigationBarItem> get _allowedNavItems {
    if (_isAdmin) {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.videocam), label: 'Trực tiếp'),
        BottomNavigationBarItem(icon: Icon(Icons.replay), label: 'Xem lại'),
        BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Sự kiện'),
        BottomNavigationBarItem(icon: Icon(Icons.apps), label: 'Thêm'),
      ];
    } else {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.videocam), label: 'Trực tiếp'),
        BottomNavigationBarItem(icon: Icon(Icons.replay), label: 'Xem lại'),
        BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Sự kiện'),
        BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: 'AI Chat'),
      ];
    }
  }

  Widget _moreGrid() {
    return Scaffold(
      appBar: AppBar(title: const Text('Tiện ích')),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        itemCount: _moreMenuItems.length,
        itemBuilder: (ctx, i) {
          final item = _moreMenuItems[i];
          return GestureDetector(
            onTap: () => setState(() => _moreSubIndex = i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: item.color, size: 26),
                ),
                const SizedBox(height: 8),
                Text(item.label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _apiService.setOnSessionExpired(_handleSessionExpired);
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    // Fetch profile to ensure the local userRole is always sync'd with the backend status
    if (_apiService.isAuthenticated) {
      await _apiService.getUserProfile();
      if (mounted) {
        setState(() {});
      }
    }
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
    // Reset "More" sub-screen when tapping "More" tab again
    if (_isAdmin && index == 3 && _currentIndex == 3 && _moreSubIndex >= 0) {
      setState(() => _moreSubIndex = -1);
      return;
    }
    if (_isAdmin && index == 3) {
      setState(() { _currentIndex = index; _moreSubIndex = -1; });
      return;
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
    final screens = _allowedScreens;
    final navItems = _allowedNavItems;
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: screens[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        items: navItems,
      ),
    );
  }
}

class _MoreItem {
  final IconData icon;
  final String label;
  final Color color;
  const _MoreItem({required this.icon, required this.label, required this.color});
}
