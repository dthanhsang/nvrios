import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera.dart';
import '../models/video_file.dart';
import '../models/face_event.dart';

typedef LogoutCallback = void Function();

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = '';
  String _localUrl = '';
  String _activeUrl = '';
  String _sessionToken = '';
  String _userRole = 'viewer';
  LogoutCallback? _onSessionExpired;

  String get baseUrl => _activeUrl.isNotEmpty ? _activeUrl : _baseUrl;
  String get rawBaseUrl => _baseUrl;
  String get localUrl => _localUrl;
  String get sessionToken => _sessionToken;
  String get userRole => _userRole;
  String get go2rtcUrl => '$baseUrl/go2rtc';
  bool get isAuthenticated => _sessionToken.isNotEmpty;

  void setOnSessionExpired(LogoutCallback callback) {
    _onSessionExpired = callback;
  }

  Map<String, String> get _headers => {
    'Cookie': 'dvr_session=$_sessionToken',
    'X-DVR-Token': _sessionToken,
    'Content-Type': 'application/x-www-form-urlencoded',
    'Bypass-Tunnel-Reminder': 'true',
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
  };

  Map<String, String> get authHeaders => {
    'Cookie': 'dvr_session=$_sessionToken',
    'X-DVR-Token': _sessionToken,
    'Bypass-Tunnel-Reminder': 'true',
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
  };

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('baseUrl') ?? '';
    _localUrl = prefs.getString('localUrl') ?? '';
    _sessionToken = prefs.getString('sessionToken') ?? '';
    _userRole = prefs.getString('userRole') ?? 'viewer';
    await detectActiveUrl();
  }

  Future<void> detectActiveUrl() async {
    if (_localUrl.isEmpty) {
      _activeUrl = _baseUrl;
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_localUrl/api/cameras'),
        headers: {'Bypass-Tunnel-Reminder': 'true'},
      ).timeout(const Duration(milliseconds: 1200));
      
      if (response.statusCode == 200 || response.statusCode == 401 || response.statusCode == 403) {
        _activeUrl = _localUrl;
        developer.log("Smart Fallback: Using Local IP/URL: $_activeUrl");
        return;
      }
    } catch (_) {}
    
    _activeUrl = _baseUrl;
    developer.log("Smart Fallback: Using Public URL: $_activeUrl");
  }

  void setBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    _activeUrl = _baseUrl;
  }

  void setLocalUrl(String url) {
    _localUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('localUrl', _localUrl);
    await prefs.setString('sessionToken', _sessionToken);
    await prefs.setString('userRole', _userRole);
  }

  Future<void> _clearCredentials() async {
    _sessionToken = '';
    _userRole = 'viewer';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionToken');
    await prefs.remove('userRole');
  }

  void _handle401(int statusCode) {
    if (statusCode == 401) {
      _clearCredentials();
      _onSessionExpired?.call();
    }
  }

  // ==================== AUTH ====================

  Future<bool> login(String username, String password) async {
    try {
      // Try JSON API login first
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['token'] != null) {
          _sessionToken = data['token'];
          _userRole = data['role'] ?? 'viewer';
          await _saveCredentials();
          return true;
        }
      }

      // Fallback: use dart:io HttpClient for redirect-based login
      final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final req = await client.postUrl(Uri.parse('$baseUrl/login'));
      req.followRedirects = false;
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write('username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}');
      final resp = await req.close();
      final cookies = resp.cookies;
      for (final cookie in cookies) {
        if (cookie.name == 'dvr_session') {
          _sessionToken = cookie.value;
          _userRole = 'viewer'; // Default to viewer for legacy cookie logins, then profile API will update it
          await _saveCredentials();
          
          // Try to fetch profile to get actual role
          await getUserProfile();
          
          client.close();
          return true;
        }
      }
      client.close();
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await http.get(Uri.parse('$baseUrl/logout'), headers: authHeaders);
    } catch (_) {}
    await _clearCredentials();
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/profile'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _userRole = data['role'] ?? 'viewer';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userRole', _userRole);
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isSessionValid() async {
    try {
      final profile = await getUserProfile();
      return profile != null;
    } catch (_) {
      return false;
    }
  }

  // ==================== CAMERAS ====================

  Future<List<Camera>> getCameras() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/cameras'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((j) => Camera.fromJson(j)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> addCamera(Map<String, String> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/cameras'),
        headers: _headers,
        body: data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&'),
      );
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateCamera(int camId, Map<String, String> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/cameras/$camId/update'),
        headers: _headers,
        body: data.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&'),
      );
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCamera(int camId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/cameras/$camId/delete'),
        headers: _headers,
      );
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== PLAYBACK ====================

  Future<List<String>> getPlaybackDates(int camId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/playback/dates/$camId'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<String>();
      }
    } catch (_) {}
    return [];
  }

  Future<List<VideoFile>> getPlaybackVideos(int camId, String date) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/playback/videos/$camId/$date'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((j) => VideoFile.fromJson(j)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getPlaybackEvents(int camId, String date) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/playback/events/$camId/$date'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data.cast<Map<String, dynamic>>();
        if (data is Map && data['events'] is List) return (data['events'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> checkPlaybackCache(int camId, String date, String filename) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/playback/cache-status/$camId/$date/$filename'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200 || response.statusCode == 202) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  String getPlayerUrl(String videoUrl, {int seekSeconds = 0}) {
    return '$baseUrl/api/playback/player?video_url=${Uri.encodeComponent(videoUrl)}&seek_seconds=$seekSeconds&token=$_sessionToken';
  }

  String getStreamUrl(int camId, String date, String filename, {int seekSeconds = 0}) {
    return '$baseUrl/api/playback/stream/$camId/$date/$filename?ss=$seekSeconds&token=$_sessionToken';
  }

  String getDirectUrl(int camId, String date, String filename) {
    return '$baseUrl/recordings/$camId/$date/$filename';
  }

  // ==================== LIVE STREAMING ====================

  String getMjpegStreamUrl(String go2rtcSrc, {bool hd = false}) {
    final src = hd ? '${go2rtcSrc}_hd_mjpeg' : '${go2rtcSrc}_mjpeg';
    return '$go2rtcUrl/api/stream.mjpeg?src=$src&token=$_sessionToken';
  }

  String getWebRtcWsUrl(String go2rtcSrc, {bool hd = false}) {
    final wsBase = _baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    final src = hd ? go2rtcSrc : '${go2rtcSrc}_sub';
    return '$wsBase/go2rtc/api/ws?src=$src&token=$_sessionToken';
  }

  String getStreamHtmlUrl(String go2rtcSrc, {bool hd = false}) {
    final src = hd ? go2rtcSrc : '${go2rtcSrc}_sub';
    return '$go2rtcUrl/stream.html?src=$src&mode=mse,webrtc&muted=1&token=$_sessionToken';
  }

  // ==================== FACE EVENTS ====================

  Future<List<FaceEvent>> getFaceEvents({int limit = 50, int? cameraId}) async {
    try {
      String url = '$baseUrl/api/faces/recent?limit=$limit';
      if (cameraId != null) url += '&camera_id=$cameraId';
      final response = await http.get(Uri.parse(url), headers: authHeaders);
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> items;
        if (data is List) {
          items = data;
        } else if (data is Map) {
          items = data['events'] as List? ?? data['faces'] as List? ?? [];
        } else {
          items = [];
        }
        return items.map((j) => FaceEvent.fromJson(j, baseUrl)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ==================== SYSTEM ====================

  Future<Map<String, dynamic>?> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/system/status'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<String> getSystemLogs({int limit = 250}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/system/logs?limit=$limit'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) return response.body;
    } catch (_) {}
    return '';
  }

  Future<bool> restartDvr() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system/restart-dvr'),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCameraHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health/cameras'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> cleanupFaces() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system/cleanup-faces'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> runDiskBenchmark() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system/disk-benchmark'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      _handle401(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> formatStorage() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/system/format-storage'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      _handle401(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  // ==================== SETTINGS ====================

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/settings'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<bool> updateSettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/settings'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(settings),
      );
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> testGemini() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/settings/test-gemini'),
        headers: _headers,
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> testAi() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/settings/test-ai'),
        headers: _headers,
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> testTelegram() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/settings/test-telegram'),
        headers: _headers,
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  // ==================== FAMILY PROFILES ====================

  Future<List<String>> getFamilyProfiles() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/system/family-profiles'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['profiles'] is List) {
          return (data['profiles'] as List).cast<String>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> uploadFamilyProfile(String filePath, String name) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/system/family-profiles/upload'),
      );
      request.headers.addAll(authHeaders);
      request.fields['name'] = name;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      final response = await request.send();
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteFamilyProfile(String filename) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/system/family-profiles/$filename'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String getFamilyProfilePhotoUrl(String filename) {
    return '$baseUrl/api/system/family-profiles/photo/$filename?token=$_sessionToken';
  }

  // ==================== SHARE LINKS ====================

  Future<List<Map<String, dynamic>>> getShareLinks() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/shares'),
        headers: authHeaders,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['shares'] is List) {
          return (data['shares'] as List).cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<bool> createShareLink({
    required int cameraId,
    required String password,
    required int expiresDays,
    required int allowPlayback,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/shares/add'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'camera_id': cameraId,
          'password': password,
          'expires_days': expiresDays,
          'allow_playback': allowPlayback,
        }),
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteShareLink(int linkId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/shares/$linkId/delete-json'),
        headers: _headers,
      );
      _handle401(response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
