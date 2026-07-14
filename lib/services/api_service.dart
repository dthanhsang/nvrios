import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = "";
  String _sessionToken = "";
  Map<String, String> _headers = {};
  String lastError = "";

  String get baseUrl => _baseUrl;
  String get sessionToken => _sessionToken;

  /// Get go2rtc base URL for live streaming
  String get go2rtcUrl => "$_baseUrl/go2rtc";

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString("baseUrl") ?? "https://dvr.dothanhsang.id.vn";
    _sessionToken = prefs.getString("sessionToken") ?? "";
    _updateHeaders();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("baseUrl", _baseUrl);
    _updateHeaders();
  }

  void _updateHeaders() {
    _headers = {
      "Content-Type": "application/json",
    };
    if (_sessionToken.isNotEmpty) {
      _headers["Cookie"] = "dvr_session=$_sessionToken";
    }
  }

  Map<String, String> get authHeaders {
    final h = Map<String, String>.from(_headers);
    h.remove("Content-Type");
    return h;
  }

  /// Cookie string for WebView injection
  String get cookieString => "dvr_session=$_sessionToken";

  Future<bool> login(String username, String password) async {
    if (_baseUrl.isEmpty) {
      lastError = "Base URL is empty";
      return false;
    }
    lastError = "";
    try {
      // Try JSON API endpoint first
      try {
        final apiLoginUrl = Uri.parse("$_baseUrl/api/login");
        final body = 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
        final apiResponse = await http.post(
          apiLoginUrl,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (apiResponse.statusCode == 200) {
          final data = jsonDecode(apiResponse.body);
          if (data['success'] == true && data['token'] != null) {
            _sessionToken = data['token'];
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString("sessionToken", _sessionToken);
            _updateHeaders();
            return true;
          } else {
            lastError = "Sai tên đăng nhập hoặc mật khẩu";
          }
        } else {
          lastError = "API HTTP ${apiResponse.statusCode}";
        }
      } catch (e) {
        lastError = "API: $e";
      }

      // Fallback: dart:io HttpClient with followRedirects=false
      final loginUrl = Uri.parse("$_baseUrl/login");
      final ioClient = HttpClient();
      ioClient.badCertificateCallback = (cert, host, port) => true;
      ioClient.connectionTimeout = const Duration(seconds: 10);
      final ioRequest = await ioClient.postUrl(loginUrl);
      ioRequest.followRedirects = false;
      ioRequest.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final bodyStr = 'username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
      final bodyBytes = utf8.encode(bodyStr);
      ioRequest.contentLength = bodyBytes.length;
      ioRequest.add(bodyBytes);
      final ioResponse = await ioRequest.close();

      if (ioResponse.statusCode == 302 || ioResponse.statusCode == 303) {
        for (var cookie in ioResponse.cookies) {
          if (cookie.name == 'dvr_session') {
            _sessionToken = cookie.value;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString("sessionToken", _sessionToken);
            _updateHeaders();
            ioClient.close();
            return true;
          }
        }
        final setCookieHeaders = ioResponse.headers['set-cookie'];
        if (setCookieHeaders != null) {
          for (var rawCookie in setCookieHeaders) {
            if (rawCookie.contains('dvr_session=')) {
              final parts = rawCookie.split(';');
              for (var part in parts) {
                if (part.trim().startsWith('dvr_session=')) {
                  _sessionToken = part.trim().substring('dvr_session='.length);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString("sessionToken", _sessionToken);
                  _updateHeaders();
                  ioClient.close();
                  return true;
                }
              }
            }
          }
        }
        lastError = "Cookie dvr_session not found";
      } else {
        lastError = "HTTP ${ioResponse.statusCode}";
      }
      ioClient.close();
      return false;
    } catch (e) {
      lastError = "Login error: $e";
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (_baseUrl.isNotEmpty) {
        await http.get(Uri.parse("$_baseUrl/logout"), headers: _headers)
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    _sessionToken = "";
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("sessionToken");
    _updateHeaders();
  }

  /// Decode response body as UTF-8 (fixes Vietnamese characters)
  String _decodeBody(http.Response response) {
    return utf8.decode(response.bodyBytes);
  }

  /// Check if session is still valid
  Future<bool> isSessionValid() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/cameras"),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ========== CAMERAS ==========

  Future<List<dynamic>> getCameras() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/cameras"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching cameras: $e");
    }
    return [];
  }

  Future<bool> updateCamera(int camId, Map<String, String> data) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/cameras/$camId/update"),
        headers: {"Content-Type": "application/x-www-form-urlencoded", ..._headers},
        body: data,
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 302 || response.statusCode == 303;
    } catch (e) {
      print("Error updating camera: $e");
      return false;
    }
  }

  Future<bool> addCamera(Map<String, String> data) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/cameras"),
        headers: {"Content-Type": "application/x-www-form-urlencoded", ..._headers},
        body: data,
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 302 || response.statusCode == 303;
    } catch (e) {
      print("Error adding camera: $e");
      return false;
    }
  }

  Future<bool> deleteCamera(int camId) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/cameras/$camId/delete"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 302 || response.statusCode == 303;
    } catch (e) {
      print("Error deleting camera: $e");
      return false;
    }
  }

  // ========== PLAYBACK ==========

  Future<List<dynamic>> getPlaybackDates(int camId) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/playback/dates/$camId"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching playback dates: $e");
    }
    return [];
  }

  Future<List<dynamic>> getPlaybackVideos(int camId, String date) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/playback/videos/$camId/$date"),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching playback videos: $e");
    }
    return [];
  }

  /// Get motion/event markers for timeline
  Future<List<dynamic>> getPlaybackEvents(int camId, String date) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/playback/events/$camId/$date"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching playback events: $e");
    }
    return [];
  }

  /// Check transcode cache status (and trigger transcode in background if needed)
  Future<Map<String, dynamic>> checkPlaybackCache(int camId, String date, String filename) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/playback/cache-status/$camId/$date/$filename"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 202) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error checking cache status: $e");
    }
    return {"status": "error"};
  }

  /// Get video stream URL (transcode endpoint)
  String getStreamUrl(int camId, String date, String filename, {int seekSeconds = 0}) {
    var url = "$_baseUrl/api/playback/stream/$camId/$date/$filename";
    if (seekSeconds > 0) {
      url += '?ss=$seekSeconds';
    }
    return url;
  }

  /// Get direct file URL
  String getDirectUrl(int camId, String date, String filename) {
    return "$_baseUrl/recordings/$camId/$date/$filename";
  }

  /// Get download URL
  String getDownloadUrl(int camId, String date, String filename) {
    return "$_baseUrl/recordings/$camId/$date/$filename";
  }

  // ========== FACE EVENTS ==========

  Future<List<dynamic>> getFaceEvents({int limit = 50, int? cameraId}) async {
    try {
      var urlStr = "$_baseUrl/api/faces/recent?limit=$limit";
      if (cameraId != null) {
        urlStr += "&camera_id=$cameraId";
      }
      final response = await http.get(
        Uri.parse(urlStr),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(_decodeBody(response));
        if (data is List) return data;
        if (data is Map && data.containsKey("events")) return data["events"];
        if (data is Map && data.containsKey("faces")) return data["faces"];
      }
    } catch (e) {
      print("Error fetching face events: $e");
    }
    return [];
  }

  // ========== SYSTEM ==========

  Future<Map<String, dynamic>> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/system/status"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching system status: $e");
    }
    return {};
  }

  Future<String> getSystemLogs({int limit = 150}) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/system/logs?limit=$limit"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return _decodeBody(response);
      }
    } catch (e) {
      print("Error fetching system logs: $e");
    }
    return "";
  }

  Future<bool> restartDvr() async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/system/restart-dvr"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print("Error restarting DVR: $e");
      return false;
    }
  }

  /// Camera health check - returns list of camera recording statuses
  Future<List<dynamic>> getCameraHealth() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/health/cameras"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching camera health: $e");
    }
    return [];
  }

  /// Cleanup face images
  Future<bool> cleanupFaces() async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/system/cleanup-faces"),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      print("Error cleaning up faces: $e");
      return false;
    }
  }

  // ========== SETTINGS ==========

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/settings"),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error fetching settings: $e");
    }
    return null;
  }

  Future<bool> updateSettings(Map<String, dynamic> settings) async {
    try {
      final headers = Map<String, String>.from(_headers);
      headers["Content-Type"] = "application/json";
      final response = await http.post(
        Uri.parse("$_baseUrl/api/settings"),
        headers: headers,
        body: jsonEncode(settings),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print("Error updating settings: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> testGemini() async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/settings/test-gemini"),
        headers: _headers,
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        return jsonDecode(_decodeBody(response));
      }
    } catch (e) {
      print("Error testing Gemini: $e");
    }
    return null;
  }
}
