import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverController = TextEditingController(text: "https://dvr.dothanhsang.id.vn");
  final _usernameController = TextEditingController(text: "admin");
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    await _apiService.init();
    if (_apiService.baseUrl.isNotEmpty && _apiService.sessionToken.isNotEmpty) {
      _navigateToMain();
    }
  }

  void _navigateToMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    final serverUrl = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Vui lòng nhập đầy đủ thông tin.";
      });
      return;
    }

    await _apiService.setBaseUrl(serverUrl);
    final success = await _apiService.login(username, password);

    setState(() {
      _isLoading = false;
    });

    if (success) {
      _navigateToMain();
    } else {
      setState(() {
        _errorMessage = "Đăng nhập thất bại: ${_apiService.lastError}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            color: const Color(0xFF161920),
            elevation: 8.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.security,
                    size: 80,
                    color: Color(0xFFFF3B30),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Đầu ghi hình DVR",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Đăng nhập hệ thống giám sát",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7E8B9B),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _serverController,
                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                    decoration: InputDecoration(
                      labelText: "Địa chỉ đầu ghi (Server URL)",
                      labelStyle: const TextStyle(color: Color(0xFF7E8B9B)),
                      prefixIcon: const Icon(Icons.dns, color: Color(0xFF7E8B9B)),
                      filled: true,
                      fillColor: const Color(0xFF1E2330),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFFF3B30)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                    decoration: InputDecoration(
                      labelText: "Tên đăng nhập",
                      labelStyle: const TextStyle(color: Color(0xFF7E8B9B)),
                      prefixIcon: const Icon(Icons.person, color: Color(0xFF7E8B9B)),
                      filled: true,
                      fillColor: const Color(0xFF1E2330),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFFF3B30)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                    decoration: InputDecoration(
                      labelText: "Mật khẩu",
                      labelStyle: const TextStyle(color: Color(0xFF7E8B9B)),
                      prefixIcon: const Icon(Icons.lock, color: Color(0xFF7E8B9B)),
                      filled: true,
                      fillColor: const Color(0xFF1E2330),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFFF3B30)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    obscureText: true,
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: Color(0xFFFF3B30)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Đăng nhập",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
