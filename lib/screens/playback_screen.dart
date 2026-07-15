import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../services/api_service.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<dynamic> _cameras = [];
  List<dynamic> _videos = [];
  List<dynamic> _events = [];
  Set<String> _recordedDates = {};

  int? _selectedCamId;
  DateTime _selectedDate = DateTime.now();
  int _playingIndex = -1;
  bool _isLoadingCams = true;
  bool _isLoadingVideos = false;

  // Transcoding state
  Timer? _transcodeTimer;
  bool _isTranscoding = false;
  String _transcodeStatusText = "";
  String? _resolvedVideoUrl;

  // Timeline state
  double _timelineZoom = 1.0; // 1 = 24h view, 4 = 6h, 24 = 1h
  double _currentPlaySeconds = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _transcodeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final cams = await _apiService.getCameras();
    setState(() {
      _cameras = cams.where((c) => c['enabled'] == 1 || c['enabled'] == true).toList();
      _isLoadingCams = false;
      if (_cameras.isNotEmpty) {
        _selectedCamId = _cameras[0]['id'];
        _loadDatesAndVideos(_selectedCamId!, _selectedDate);
      }
    });
  }

  Future<void> _loadDatesAndVideos(int camId, DateTime date) async {
    _transcodeTimer?.cancel();
    setState(() {
      _isLoadingVideos = true;
      _videos = [];
      _events = [];
      _playingIndex = -1;
      _currentPlaySeconds = 0;
      _isTranscoding = false;
      _resolvedVideoUrl = null;
    });

    try {
      final dateStr = _formatDate(date);
      // Run concurrent requests
      final results = await Future.wait([
        _apiService.getPlaybackDates(camId),
        _apiService.getPlaybackVideos(camId, dateStr),
        _apiService.getPlaybackEvents(camId, dateStr),
      ]);

      final dates = results[0] as List<dynamic>;
      final videos = results[1] as List<dynamic>;
      final events = results[2] as List<dynamic>;

      setState(() {
        _recordedDates = dates.map((d) => d.toString()).toSet();
        _videos = videos..sort((a, b) => (a['start_seconds'] ?? 0).compareTo(b['start_seconds'] ?? 0));
        _events = events;
        _isLoadingVideos = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingVideos = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi tải dữ liệu: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  }

  String _formatDuration(dynamic secondsOpt) {
    if (secondsOpt == null) return "00:00";
    int seconds = 0;
    if (secondsOpt is double) seconds = secondsOpt.toInt();
    else if (secondsOpt is int) seconds = secondsOpt;

    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _formatSecondsToTime(double secs) {
    final h = (secs ~/ 3600).clamp(0, 23);
    final m = ((secs % 3600) ~/ 60).clamp(0, 59);
    final s = (secs % 60).toInt().clamp(0, 59);
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _parseTimeFromFilename(String filename) {
    try {
      final clean = filename.replaceAll(".mp4", "");
      final parts = clean.split("-");
      if (parts.length >= 3) return "${parts[0]}:${parts[1]}:${parts[2]}";
    } catch (_) {}
    return filename;
  }

  bool _checkCanPlayDirect(Map<String, dynamic> video) {
    final codec = (video['codec'] ?? "").toString().toLowerCase();
    final pixFmt = (video['pix_fmt'] ?? "").toString().toLowerCase();
    if ((codec == "h264" || codec == "avc") && !pixFmt.contains("yuvj")) {
      return true;
    }
    if (video['has_cache'] == true) {
      return true;
    }
    return false;
  }

  void _playVideoAtIndex(int index, {int seekSeconds = 0}) {
    if (index < 0 || index >= _videos.length) return;
    _transcodeTimer?.cancel();
    final video = Map<String, dynamic>.from(_videos[index]);

    setState(() {
      _playingIndex = index;
      _currentPlaySeconds = (video['start_seconds'] ?? 0).toDouble() + seekSeconds;
    });

    final isDirect = _checkCanPlayDirect(video);

    if (isDirect) {
      final String path = video['cache_url'] ?? video['direct_url'] ?? video['url'];
      setState(() {
        _isTranscoding = false;
        _resolvedVideoUrl = _addTokenToUrl(path.startsWith("http") ? path : "${_apiService.baseUrl}$path");
      });
    } else {
      // Needs transcoding. Check status and start polling.
      _checkCacheAndPlay(video, seekSeconds);
    }
  }

  String _addTokenToUrl(String url) {
    if (url.isEmpty) return url;
    final token = _apiService.sessionToken;
    if (token.isEmpty) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}token=$token';
  }

  Future<void> _checkCacheAndPlay(Map<String, dynamic> video, int seekSeconds) async {
    setState(() {
      _isTranscoding = true;
      _transcodeStatusText = "⏳ Đang tối ưu định dạng video H.265...";
      _resolvedVideoUrl = null;
    });

    final filename = video['filename'];
    final dateStr = _formatDate(_selectedDate);

    // Immediate check
    final status = await _apiService.checkPlaybackCache(_selectedCamId!, dateStr, filename);
    if (status['status'] == 'ready') {
      final String path = status['url'];
      setState(() {
        _isTranscoding = false;
        _resolvedVideoUrl = _addTokenToUrl(path.startsWith("http") ? path : "${_apiService.baseUrl}$path");
      });
      return;
    }

    // Start polling
    int pollCount = 0;
    _transcodeTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      pollCount++;
      if (pollCount > 150) { // Limit 5 minutes
        timer.cancel();
        setState(() {
          _transcodeStatusText = "❌ Lỗi: Quá thời gian chuyển đổi video. Vui lòng thử lại.";
        });
        return;
      }

      if (!mounted) {
        timer.cancel();
        return;
      }

      final check = await _apiService.checkPlaybackCache(_selectedCamId!, dateStr, filename);
      if (check['status'] == 'ready') {
        timer.cancel();
        final String path = check['url'];
        setState(() {
          _isTranscoding = false;
          _resolvedVideoUrl = _addTokenToUrl(path.startsWith("http") ? path : "${_apiService.baseUrl}$path");
        });
      } else {
        setState(() {
          _transcodeStatusText = "⏳ Đang chuyển đổi video (H.265 → H.264)...\nĐã đợi ${pollCount * 2}s. Vui lòng chờ.";
        });
      }
    });
  }

  void _seekOnTimeline(double fraction) {
    if (_videos.isEmpty) return;
    final targetSeconds = fraction * 86400;

    // Find clip containing this time
    for (int i = 0; i < _videos.length; i++) {
      final v = _videos[i];
      final start = (v['start_seconds'] ?? 0).toDouble();
      final dur = (v['duration'] ?? 600).toDouble();
      if (targetSeconds >= start && targetSeconds <= start + dur) {
        _playVideoAtIndex(i, seekSeconds: (targetSeconds - start).toInt());
        return;
      }
    }

    // No exact match - find nearest clip after this point
    for (int i = 0; i < _videos.length; i++) {
      final start = (_videos[i]['start_seconds'] ?? 0).toDouble();
      if (start > targetSeconds) {
        _playVideoAtIndex(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Xem lại ghi hình"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, size: 22),
            onPressed: _showDatePicker,
            tooltip: "Chọn ngày",
          ),
        ],
      ),
      body: _isLoadingCams
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : Column(
              children: [
                _buildCameraSelector(),
                _buildDateChips(),
                if (_playingIndex >= 0) _buildPlayerSection(),
                _buildTimeline(),
                Expanded(child: _buildVideoList()),
              ],
            ),
    );
  }

  Widget _buildCameraSelector() {
    return Container(
      height: 44,
      color: const Color(0xFF161920),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _cameras.length,
        itemBuilder: (context, index) {
          final cam = _cameras[index];
          final isActive = cam['id'] == _selectedCamId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedCamId = cam['id']);
                _loadDatesAndVideos(cam['id'], _selectedDate);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF2A3142),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 14,
                      color: isActive ? Colors.white : const Color(0xFF7E8B9B)),
                    const SizedBox(width: 6),
                    Text(
                      cam['name'] ?? 'Camera ${cam['id']}',
                      style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF7E8B9B),
                        fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateChips() {
    final today = DateTime.now();
    final dates = List.generate(7, (i) => today.subtract(Duration(days: i)));
    final weekdayNames = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Container(
      height: 56,
      color: const Color(0xFF12141A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final d = dates[index];
          final dateStr = _formatDate(d);
          final isSelected = _formatDate(_selectedDate) == dateStr;
          final hasRecording = _recordedDates.contains(dateStr);

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedDate = d);
                if (_selectedCamId != null) {
                  _loadDatesAndVideos(_selectedCamId!, d);
                }
              },
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFF3B30)
                           : hasRecording ? const Color(0xFF3E4556) : const Color(0xFF232731),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekdayNames[d.weekday],
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF7E8B9B),
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.day.toString(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                        fontSize: 16, fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasRecording && !isSelected)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4, height: 4,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFF3B30),
              onPrimary: Colors.white,
              surface: Color(0xFF161920),
              onSurface: Color(0xFFE2E8F0),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      if (_selectedCamId != null) {
        _loadDatesAndVideos(_selectedCamId!, picked);
      }
    }
  }

  Widget _buildPlayerSection() {
    if (_playingIndex < 0 || _playingIndex >= _videos.length) return const SizedBox.shrink();
    final video = _videos[_playingIndex];
    final dateStr = _formatDate(_selectedDate);
    
    final double startSecs = (video['start_seconds'] ?? 0).toDouble();
    final int seekDiff = (_currentPlaySeconds - startSecs).clamp(0.0, (video['duration'] ?? 600.0).toDouble()).toInt();
    
    final cookie = _apiService.cookieString;

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: _isTranscoding
                ? Container(
                    color: const Color(0xFF0F1115),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFFFF3B30)),
                            const SizedBox(height: 16),
                            Text(
                              _transcodeStatusText,
                              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _resolvedVideoUrl == null
                    ? Container(color: Colors.black)
                    : _PlaybackWebView(
                        key: ValueKey('play_${_selectedCamId}_${video['filename']}_${seekDiff}_$_resolvedVideoUrl'),
                        videoUrl: _resolvedVideoUrl!,
                        seekSeconds: seekDiff,
                        cookie: cookie,
                        baseUrl: _apiService.baseUrl,
                        sessionToken: _apiService.sessionToken,
                        onEnded: () {
                          // Auto-play next clip
                          if (_playingIndex < _videos.length - 1) {
                            _playVideoAtIndex(_playingIndex + 1);
                          }
                        },
                        onTimeUpdate: (seconds) {
                          if (mounted) {
                            setState(() {
                              _currentPlaySeconds = startSecs + seconds;
                            });
                          }
                        },
                      ),
          ),
          // Info bar below player
          Container(
            color: const Color(0xFF161920),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatSecondsToTime(_currentPlaySeconds),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${_parseTimeFromFilename(video['filename'])} \u2022 ${_formatDuration(video['duration'] ?? 0)} \u2022 ${video['codec']?.toString().toUpperCase() ?? 'H.264'}",
                    style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Download button
                GestureDetector(
                  onTap: () {
                    final base = _apiService.baseUrl;
                    final downloadUrl = "$base/recordings/$_selectedCamId/$dateStr/${video['filename']}";
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: SelectableText("Tải video: $downloadUrl", style: const TextStyle(color: Colors.white)),
                        backgroundColor: const Color(0xFF1E2330),
                      ),
                    );
                  },
                  child: const Icon(Icons.download, color: Color(0xFFFF3B30), size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_videos.isEmpty && !_isLoadingVideos) return const SizedBox.shrink();

    return Container(
      height: 76,
      color: const Color(0xFF11141A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          // Zoom buttons row
          SizedBox(
            height: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _zoomButton("24h", 1.0),
                _zoomButton("6h", 4.0),
                _zoomButton("1h", 24.0),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Timeline track
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth * _timelineZoom;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: GestureDetector(
                    onTapDown: (details) {
                      final fraction = details.localPosition.dx / totalWidth;
                      _seekOnTimeline(fraction.clamp(0.0, 1.0));
                    },
                    onHorizontalDragUpdate: (details) {
                      final fraction = details.localPosition.dx / totalWidth;
                      _seekOnTimeline(fraction.clamp(0.0, 1.0));
                    },
                    child: SizedBox(
                      width: totalWidth,
                      child: CustomPaint(
                        painter: _TimelinePainter(
                          videos: _videos,
                          events: _events,
                          currentSeconds: _currentPlaySeconds,
                          zoom: _timelineZoom,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomButton(String label, double zoom) {
    final isActive = _timelineZoom == zoom;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
        onTap: () => setState(() => _timelineZoom = zoom),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isActive ? const Color(0xFFFF3B30) : const Color(0xFF2A3142)),
          ),
          child: Text(label,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF7E8B9B),
              fontSize: 9, fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    if (_isLoadingVideos) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)));
    }
    if (_videos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, size: 48, color: Color(0xFF7E8B9B)),
            SizedBox(height: 12),
            Text("Không có video ghi hình cho ngày này.",
              style: TextStyle(color: Color(0xFF7E8B9B), fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final isPlaying = index == _playingIndex;
        final startTime = _parseTimeFromFilename(video['filename']);
        final codec = video['codec']?.toString().toUpperCase() ?? 'H.264';
        final isHevc = codec == 'HEVC' || codec == 'H265';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isPlaying ? const Color(0xFF1E2330) : const Color(0xFF161920),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPlaying ? const Color(0xFFFF3B30) : const Color(0xFF232731),
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isPlaying ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: isPlaying ? Colors.white : const Color(0xFF7E8B9B),
                size: 20,
              ),
            ),
            title: Text(startTime,
              style: TextStyle(
                color: isPlaying ? const Color(0xFFFF3B30) : const Color(0xFFE2E8F0),
                fontWeight: FontWeight.w700, fontSize: 14,
              ),
            ),
            subtitle: Text(
              "${_formatDuration(video['duration'] ?? 0)} \u2022 ${video['size_mb']?.toStringAsFixed(1) ?? '0.0'} MB",
              style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 11),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isHevc ? const Color(0xFF2D1F3D) : const Color(0xFF1F2D3D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(codec,
                style: TextStyle(
                  color: isHevc ? Colors.purple[200] : const Color(0xFF60A5FA),
                  fontSize: 9, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () => _playVideoAtIndex(index),
          ),
        );
      },
    );
  }
}

// ===== TIMELINE PAINTER =====
class _TimelinePainter extends CustomPainter {
  final List<dynamic> videos;
  final List<dynamic> events;
  final double currentSeconds;
  final double zoom;

  _TimelinePainter({
    required this.videos,
    required this.events,
    required this.currentSeconds,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF1E2330);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 8, size.width, size.height - 8), const Radius.circular(4)),
      bgPaint,
    );

    // Draw recording blocks (green)
    final blockPaint = Paint()..color = const Color(0x732ECC71);
    for (var v in videos) {
      final start = (v['start_seconds'] ?? 0).toDouble();
      final dur = (v['duration'] ?? 600.0).toDouble();
      final x = (start / 86400) * size.width;
      final w = (dur / 86400) * size.width;
      canvas.drawRect(Rect.fromLTWH(x, 8, w, size.height - 8), blockPaint);
    }

    // Draw event markers (red dots)
    final eventPaint = Paint()..color = const Color(0xFFE60012);
    for (var ev in events) {
      final sec = (ev['seconds'] ?? 0).toDouble();
      final x = (sec / 86400) * size.width;
      canvas.drawRect(Rect.fromLTWH(x, 8, 2, size.height - 8), eventPaint);
    }

    // Draw time ticks
    int intervalMinutes = 120;
    if (zoom >= 24) intervalMinutes = 10;
    else if (zoom >= 4) intervalMinutes = 30;

    final tickPaint = Paint()..color = const Color(0xFF3E4556);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int m = 0; m <= 24 * 60; m += intervalMinutes) {
      final x = (m / 1440) * size.width;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, 6), tickPaint);

      final h = m ~/ 60;
      final min = m % 60;
      final label = "${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}";
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFF7E8B9B), fontSize: 8),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 0));
    }

    // Draw playback handle (red line)
    if (currentSeconds > 0) {
      final handleX = (currentSeconds / 86400) * size.width;
      final handlePaint = Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(handleX, 0), Offset(handleX, size.height), handlePaint);

      // Small circle at top
      canvas.drawCircle(Offset(handleX, 4), 4, handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.currentSeconds != currentSeconds ||
        oldDelegate.zoom != zoom ||
        oldDelegate.videos.length != videos.length;
  }
}

// ===== PLAYBACK WEBVIEW =====
class _PlaybackWebView extends StatefulWidget {
  final String videoUrl;
  final int seekSeconds;
  final String cookie;
  final String baseUrl;
  final String sessionToken;
  final VoidCallback? onEnded;
  final ValueChanged<double>? onTimeUpdate;

  const _PlaybackWebView({
    super.key,
    required this.videoUrl,
    required this.seekSeconds,
    required this.cookie,
    required this.baseUrl,
    required this.sessionToken,
    this.onEnded,
    this.onTimeUpdate,
  });

  @override
  State<_PlaybackWebView> createState() => _PlaybackWebViewState();
}

class _PlaybackWebViewState extends State<_PlaybackWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // Set cookie via WebViewCookieManager for iOS compatibility (WKWebView)
    final cookieManager = WebViewCookieManager();
    final uri = Uri.parse(widget.baseUrl);
    
    try {
      await cookieManager.setCookie(WebViewCookie(
        name: 'dvr_session',
        value: widget.sessionToken,
        domain: uri.host,
        path: '/',
      ));
    } catch (e) {
      // Fallback: cookie will be set via JavaScript in the HTML
      debugPrint('Cookie manager failed, using JS fallback: $e');
    }
    
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller
      ..addJavaScriptChannel('Flutter', onMessageReceived: (message) {
        final msg = message.message;
        if (msg == 'ended' && widget.onEnded != null) {
          widget.onEnded!();
        } else if (msg.startsWith('time:') && widget.onTimeUpdate != null) {
          final secs = double.tryParse(msg.substring(5)) ?? 0;
          widget.onTimeUpdate!(secs);
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      ));

    final playerUrl = "${widget.baseUrl}/api/playback/player"
        "?video_url=${Uri.encodeComponent(widget.videoUrl)}"
        "&seek_seconds=${widget.seekSeconds}"
        "&token=${widget.sessionToken}";

    _controller.loadRequest(
      Uri.parse(playerUrl),
      headers: {
        'Bypass-Tunnel-Reminder': 'true',
        'X-DVR-Token': widget.sessionToken,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30), strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}
