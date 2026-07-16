import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'main_screen.dart';

// SharedPreferences keys for saved credentials
const _kRememberLogin = 'remember_login';
const _kSavedServer = 'saved_server';
const _kSavedUsername = 'saved_username';
const _kSavedPassword = 'saved_password';
const _kBiometricEnabled = 'biometric_enabled';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _apiService = ApiService();
  final _localAuth = LocalAuthentication();

  final _serverController =
      TextEditingController(text: 'https://dvr.dothanhsang.id.vn');
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  bool _rememberLogin = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  List<BiometricType> _availableBiometrics = [];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
    _initializeLogin();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _initializeLogin() async {
    await _checkBiometricAvailability();
    await _loadSavedCredentials();
    await _tryAutoLogin();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (canCheck && isDeviceSupported) {
        final biometrics = await _localAuth.getAvailableBiometrics();
        if (mounted) {
          setState(() {
            _biometricAvailable = biometrics.isNotEmpty;
            _availableBiometrics = biometrics;
          });
        }
      }
    } on PlatformException catch (_) {
      // Biometric not available on this device
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRememberLogin) ?? false;
    final biometric = prefs.getBool(_kBiometricEnabled) ?? false;

    if (remember) {
      final server = prefs.getString(_kSavedServer) ?? '';
      final username = prefs.getString(_kSavedUsername) ?? '';
      final password = prefs.getString(_kSavedPassword) ?? '';

      if (mounted) {
        setState(() {
          _rememberLogin = true;
          _biometricEnabled = biometric && _biometricAvailable;
          if (server.isNotEmpty) _serverController.text = server;
          if (username.isNotEmpty) _usernameController.text = username;
          if (password.isNotEmpty) _passwordController.text = password;
        });
      }
    }
  }

  Future<void> _tryAutoLogin() async {
    await _apiService.init();

    // First: try restoring an existing valid session
    if (_apiService.isAuthenticated) {
      if (mounted) setState(() => _isLoading = true);
      final valid = await _apiService.isSessionValid();
      if (valid && mounted) {
        _navigateToMain();
        return;
      }
      if (mounted) setState(() => _isLoading = false);
    }

    // Populate server URL from API service if available
    if (_apiService.baseUrl.isNotEmpty) {
      _serverController.text = _apiService.baseUrl;
    }

    // If credentials are saved, try auto-login with them
    if (_rememberLogin && _passwordController.text.isNotEmpty) {
      // If biometric is enabled, prompt biometric first
      if (_biometricEnabled && _biometricAvailable) {
        await _loginWithBiometric();
      } else {
        await _login(isAutoLogin: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Credential persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberLogin) {
      await prefs.setBool(_kRememberLogin, true);
      await prefs.setString(_kSavedServer, _serverController.text.trim());
      await prefs.setString(_kSavedUsername, _usernameController.text.trim());
      await prefs.setString(_kSavedPassword, _passwordController.text);
      await prefs.setBool(_kBiometricEnabled, _biometricEnabled);
    } else {
      await _clearSavedCredentials(prefs);
    }
  }

  Future<void> _clearSavedCredentials([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_kRememberLogin);
    await prefs.remove(_kSavedServer);
    await prefs.remove(_kSavedUsername);
    await prefs.remove(_kSavedPassword);
    await prefs.remove(_kBiometricEnabled);
  }

  // ---------------------------------------------------------------------------
  // Login methods
  // ---------------------------------------------------------------------------

  Future<void> _login({bool isAutoLogin = false}) async {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Vui lòng điền đầy đủ thông tin');
      return;
    }

    // Basic URL validation
    if (!server.startsWith('http://') && !server.startsWith('https://')) {
      setState(() => _error = 'Địa chỉ máy chủ phải bắt đầu bằng http:// hoặc https://');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _apiService.setBaseUrl(server);
      final success = await _apiService.login(username, password);

      if (!mounted) return;

      if (success) {
        await _saveCredentials();
        _navigateToMain();
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Sai tên đăng nhập hoặc mật khẩu';
        });
      }
    } on SocketException catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Không thể kết nối đến máy chủ. Kiểm tra địa chỉ và kết nối mạng.';
      });
    } on HttpException catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Lỗi HTTP từ máy chủ. Vui lòng thử lại.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = isAutoLogin
            ? 'Đăng nhập tự động thất bại. Vui lòng đăng nhập thủ công.'
            : 'Đã xảy ra lỗi: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e}';
      });
    }
  }

  Future<void> _loginWithBiometric() async {
    if (!_biometricAvailable) return;

    // Need saved credentials to do biometric login
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Chưa có thông tin đăng nhập được lưu cho xác thực sinh trắc học.');
      return;
    }

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Xác thực để đăng nhập vào WebDVR',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        await _login();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'NotAvailable':
          message = 'Sinh trắc học không khả dụng trên thiết bị này.';
          break;
        case 'NotEnrolled':
          message = 'Chưa đăng ký sinh trắc học. Vui lòng thiết lập trong Cài đặt.';
          break;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          message = 'Sinh trắc học đã bị khóa. Vui lòng thử lại sau.';
          break;
        default:
          message = 'Xác thực sinh trắc học thất bại.';
      }
      setState(() => _error = message);
    }
  }

  void _navigateToMain() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _biometricLabel() {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Touch ID';
    }
    return 'Sinh trắc học';
  }

  IconData _biometricIcon() {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    }
    return Icons.fingerprint;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1115), Color(0xFF1A1D24)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildServerField(),
                    const SizedBox(height: 16),
                    _buildUsernameField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(),
                    const SizedBox(height: 12),
                    _buildRememberRow(),
                    if (_biometricAvailable && _rememberLogin) ...[
                      const SizedBox(height: 4),
                      _buildBiometricToggle(),
                    ],
                    _buildErrorMessage(),
                    const SizedBox(height: 20),
                    _buildLoginButton(),
                    if (_biometricAvailable &&
                        _biometricEnabled &&
                        _passwordController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildBiometricButton(),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Phiên bản 2.1.0',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            color: Color(0xFFFF3B30),
            size: 42,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'WebDVR',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Hệ thống camera giám sát',
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildServerField() {
    return TextField(
      controller: _serverController,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        labelText: 'Địa chỉ máy chủ',
        prefixIcon: Icon(Icons.dns_outlined),
        hintText: 'https://example.com',
      ),
      keyboardType: TextInputType.url,
      enabled: !_isLoading,
    );
  }

  Widget _buildUsernameField() {
    return TextField(
      controller: _usernameController,
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        labelText: 'Tên đăng nhập',
        prefixIcon: Icon(Icons.person_outline),
      ),
      enabled: !_isLoading,
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      style: const TextStyle(color: Colors.white),
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Mật khẩu',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      onSubmitted: (_) => _login(),
      enabled: !_isLoading,
    );
  }

  Widget _buildRememberRow() {
    return Row(
      children: [
        SizedBox(
          height: 28,
          width: 28,
          child: Checkbox(
            value: _rememberLogin,
            onChanged: _isLoading
                ? null
                : (value) {
                    setState(() {
                      _rememberLogin = value ?? false;
                      if (!_rememberLogin) {
                        _biometricEnabled = false;
                        _clearSavedCredentials();
                      }
                    });
                  },
            activeColor: const Color(0xFFFF3B30),
            side: BorderSide(color: Colors.grey[600]!),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isLoading
              ? null
              : () {
                  setState(() {
                    _rememberLogin = !_rememberLogin;
                    if (!_rememberLogin) {
                      _biometricEnabled = false;
                      _clearSavedCredentials();
                    }
                  });
                },
          child: Text(
            'Ghi nhớ đăng nhập',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricToggle() {
    return Row(
      children: [
        SizedBox(
          height: 28,
          width: 28,
          child: Checkbox(
            value: _biometricEnabled,
            onChanged: _isLoading
                ? null
                : (value) {
                    setState(() => _biometricEnabled = value ?? false);
                  },
            activeColor: const Color(0xFFFF3B30),
            side: BorderSide(color: Colors.grey[600]!),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          _biometricIcon(),
          color: Colors.grey[400],
          size: 18,
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _isLoading
              ? null
              : () {
                  setState(
                      () => _biometricEnabled = !_biometricEnabled);
                },
          child: Text(
            'Đăng nhập bằng ${_biometricLabel()}',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFF3B30).withOpacity(0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              color: Color(0xFFFF3B30),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF3B30),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF3B30),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFFF3B30).withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Đăng nhập',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _loginWithBiometric,
        icon: Icon(_biometricIcon(), size: 22),
        label: Text(
          'Đăng nhập bằng ${_biometricLabel()}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.grey[600]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
