import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// Dịch vụ cache offline — lưu dữ liệu API vào SharedPreferences để xem khi mất mạng.
class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const _prefix = 'offline_cache_';

  // ==================== Core Cache Methods ====================

  /// Lưu dữ liệu vào cache kèm timestamp.
  Future<void> cacheData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    final wrapper = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    await prefs.setString('$_prefix$key', jsonEncode(wrapper));
  }

  /// Đọc dữ liệu từ cache. Trả về null nếu không có hoặc đã quá hạn.
  Future<dynamic> getCachedData(String key, {Duration maxAge = const Duration(days: 7)}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;

    try {
      final wrapper = jsonDecode(raw);
      final timestamp = wrapper['timestamp'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > maxAge.inMilliseconds) return null;
      return wrapper['data'];
    } catch (_) {
      return null;
    }
  }

  /// Xóa toàn bộ cache offline.
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Kiểm tra kết nối tới server bằng HEAD request nhanh.
  Future<bool> isOnline() async {
    try {
      final api = ApiService();
      final response = await http.head(
        Uri.parse('${api.baseUrl}/api/cameras'),
        headers: api.authHeaders,
      ).timeout(const Duration(seconds: 3));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ==================== Convenience Cache Keys ====================

  String cameraListKey() => 'cameras';
  String eventsKey(int camId) => 'events_$camId';
  String analyticsSummaryKey(int? camId) => 'analytics_summary_${camId ?? 'all'}';
  String analyticsHourlyKey(int? camId, String date) => 'analytics_hourly_${camId ?? 'all'}_$date';
  String floorplanKey() => 'floorplan';

  // ==================== Wrapper: fetch API with cache fallback ====================

  /// Gọi API, cache kết quả. Nếu mất mạng thì trả về cache cũ.
  Future<T?> fetchWithCache<T>({
    required String cacheKey,
    required Future<T?> Function() apiFetch,
    required T? Function(dynamic json) fromCache,
    required dynamic Function(T data) toCache,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final result = await apiFetch();
      if (result != null) {
        await cacheData(cacheKey, toCache(result));
        return result;
      }
    } catch (_) {
      // Network error — fall through to cache
    }

    // Fallback to cache
    final cached = await getCachedData(cacheKey, maxAge: maxAge);
    if (cached != null) {
      return fromCache(cached);
    }
    return null;
  }
}
