import 'dart:convert';
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
  String _sessionToken = '';
  LogoutCallback? _onSessionExpired;

  String get baseUrl => _baseUrl;
  String get sessionToken => _sessionToken;
  String get go2rtcUrl => '$_baseUrl/go2rtc';
  bool get isAuthenticated => _sessionToken.isNotEmpty;

  void setOnSessionExpired(LogoutCallback callback) {
    _onSessionExpired = callback;
  }

  Map<String, String> get _headers => {
    'Cookie': 'dvr_session=$_sessionToken',
    'X-DVR-Token': _sessionToken,
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  Map<String, String> get authHeaders => {
    'Cookie': 'dvr_session=$_sessionToken',
    'X-DVR-Token': _sessionToken,
  };

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('baseUrl') ?? '';
    _sessionToken = prefs.getString('sessionToken') ?? '';
  }

  void setBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', _baseUrl);
    await prefs.setString('sessionToken', _sessionToken);
  }

  Future<void> _clearCredentials() async {
    _sessionToken = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionToken');
  }

  void _handle401(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      _clearCredentials();
      _onSessionExpired?.call();
    }
  }

  // ==================== AUTH ====================

  Future<bool> login(String username, String password) async {
    try {
      // Try JSON API login first
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['token'] != null) {
          _sessionToken = data['token'];
          await _saveCredentials();
          return true;
        }
      }

      // Fallback: use dart:io HttpClient for redirect-based login
      final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final req = await client.postUrl(Uri.parse('$_baseUrl/login'));
      req.followRedirects = false;
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write('username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}');
      final resp = await req.close();
      final cookies = resp.cookies;
      for (final cookie in cookies) {
        if (cookie.name == 'dvr_session') {
          _sessionToken = cookie.value;
          await _saveCredentials();
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
      await http.get(Uri.parse('$_baseUrl/logout'), headers: authHeaders);
    } catch (_) {}
    await _clearCredentials();
  }

  Future<bool> isSessionValid() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/cameras'),
        headers: authHeaders,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== CAMERAS ====================

  Future<List<Camera>> getCameras() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/cameras'),
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
        Uri.parse('$_baseUrl/api/cameras'),
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
        Uri.parse('$_baseUrl/api/cameras/$camId/update'),
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
        Uri.parse('$_baseUrl/api/cameras/$camId/delete'),
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
        Uri.parse('$_baseUrl/api/playback/dates/$camId'),
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
        Uri.parse('$_baseUrl/api/playback/videos/$camId/$date'),
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
        Uri.parse('$_baseUrl/api/playback/events/$camId/$date'),
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
        Uri.parse('$_baseUrl/api/playback/cache-status/$camId/$date/$filename'),
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
    return '$_baseUrl/api/playback/player?video_url=${Uri.encodeComponent(videoUrl)}&seek_seconds=$seekSeconds&token=$_sessionToken';
  }

  String getStreamUrl(int camId, String date, String filename, {int seekSeconds = 0}) {
    return '$_baseUrl/api/playback/stream/$camId/$date/$filename?ss=$seekSeconds&token=$_sessionToken';
  }

  String getDirectUrl(int camId, String date, String filename) {
    return '$_baseUrl/recordings/$camId/$date/$filename';
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
      String url = '$_baseUrl/api/faces/recent?limit=$limit';
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
        return items.map((j) => FaceEvent.fromJson(j, _baseUrl)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ==================== SYSTEM ====================

  Future<Map<String, dynamic>?> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/system/status'),
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
        Uri.parse('$_baseUrl/api/system/logs?limit=$limit'),
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
        Uri.parse('$_baseUrl/api/system/restart-dvr'),
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
        Uri.parse('$_baseUrl/api/health/cameras'),
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
        Uri.parse('$_baseUrl/api/system/cleanup-faces'),
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
        Uri.parse('$_baseUrl/api/system/disk-benchmark'),
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
        Uri.parse('$_baseUrl/api/system/format-storage'),
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
        Uri.parse('$_baseUrl/api/settings'),
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
        Uri.parse('$_baseUrl/api/settings'),
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
        Uri.parse('$_baseUrl/api/settings/test-gemini'),
        headers: _headers,
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> testAi() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/test-ai'),
        headers: _headers,
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (_) {}
    return null;
  }
}
