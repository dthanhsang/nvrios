import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/camera.dart';
import '../models/video_file.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<Camera> _cameras = [];
  Camera? _selectedCamera;
  String? _selectedDate;
  List<VideoFile> _videos = [];
  List<Map<String, dynamic>> _events = [];
  List<String> _availableDates = [];
  VideoFile? _currentVideo;
  int _currentVideoIndex = -1;
  double _currentPlaySeconds = 0;
  bool _isLoading = true;
  bool _isTranscoding = false;
  String? _loadedVideoUrl;
  int _loadedSeekSeconds = 0;
  int _timelineZoom = 1; // 1=24h, 4=6h, 24=1h

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    final cameras = await _apiService.getCameras();
    if (mounted) {
      setState(() {
        _cameras = cameras.where((c) => c.enabled).toList();
        if (_cameras.isNotEmpty && _selectedCamera == null) {
          _selectedCamera = _cameras.first;
          _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          _loadDatesAndVideos();
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDatesAndVideos() async {
    if (_selectedCamera == null || _selectedDate == null) return;
    setState(() => _isLoading = true);
    
    final dates = await _apiService.getPlaybackDates(_selectedCamera!.id);
    final videos = await _apiService.getPlaybackVideos(_selectedCamera!.id, _selectedDate!);
    final events = await _apiService.getPlaybackEvents(_selectedCamera!.id, _selectedDate!);
    
    if (mounted) {
      setState(() {
        _availableDates = dates;
        _videos = videos;
        _events = events;
        _isLoading = false;
      });
    }
  }

  Future<void> _playVideo(int index, {int seekSeconds = 0}) async {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    
    // Check if transcoding needed
    if (video.needsTranscode && !video.hasCache) {
      setState(() => _isTranscoding = true);
      
      // Trigger and poll transcoding
      for (int i = 0; i < 150; i++) {
        final status = await _apiService.checkPlaybackCache(
          _selectedCamera!.id, _selectedDate!, video.filename,
        );
        if (status != null && status['status'] == 'ready') {
          break;
        }
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
      }
      
      if (mounted) setState(() => _isTranscoding = false);
    }
    
    final videoUrl = video.needsTranscode
        ? _apiService.getStreamUrl(_selectedCamera!.id, _selectedDate!, video.filename, seekSeconds: seekSeconds)
        : '${_apiService.baseUrl}${video.canPlayDirect ? video.directUrl : (video.hasCache ? video.cacheUrl ?? video.url : video.url)}';
    
    if (mounted) {
      setState(() {
        _currentVideo = video;
        _currentVideoIndex = index;
        _loadedVideoUrl = videoUrl;
        _loadedSeekSeconds = seekSeconds;
        _currentPlaySeconds = video.startSeconds.toDouble() + seekSeconds;
      });
    }
  }

  void _onVideoEnded() {
    if (_currentVideoIndex < _videos.length - 1) {
      _playVideo(_currentVideoIndex + 1);
    }
  }

  void _onTimeUpdate(double seconds) {
    if (mounted) {
      setState(() {
        _currentPlaySeconds = (_currentVideo?.startSeconds.toDouble() ?? 0) + seconds;
      });
    }
  }

  void _onTimelineTap(double totalSeconds) {
    // Find video containing this timestamp
    for (int i = 0; i < _videos.length; i++) {
      final v = _videos[i];
      if (totalSeconds >= v.startSeconds && totalSeconds < v.startSeconds + v.duration) {
        _playVideo(i, seekSeconds: (totalSeconds - v.startSeconds).toInt());
        return;
      }
    }
  }

  void _cycleZoom() {
    setState(() {
      if (_timelineZoom == 1) _timelineZoom = 4;
      else if (_timelineZoom == 4) _timelineZoom = 24;
      else _timelineZoom = 1;
    });
  }

  String get _zoomLabel {
    if (_timelineZoom == 1) return '24h';
    if (_timelineZoom == 4) return '6h';
    return '1h';
  }

  List<String> get _dateChips {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: i));
      return DateFormat('yyyy-MM-dd').format(date);
    });
  }

  String _formatDateChip(String date) {
    final dt = DateTime.parse(date);
    final weekdays = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    final day = DateFormat('dd/MM').format(dt);
    return '${weekdays[dt.weekday % 7]}\n$day';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem lại'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 20),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_selectedDate ?? '') ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDate = DateFormat('yyyy-MM-dd').format(picked));
                _loadDatesAndVideos();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera selector
          if (_cameras.isNotEmpty) SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _cameras.length,
              itemBuilder: (context, i) {
                final cam = _cameras[i];
                final selected = cam.id == _selectedCamera?.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cam.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.grey)),
                    selected: selected,
                    selectedColor: const Color(0xFFFF3B30),
                    backgroundColor: const Color(0xFF1E2330),
                    onSelected: (_) {
                      setState(() => _selectedCamera = cam);
                      _loadDatesAndVideos();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // Date selector
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _dateChips.length,
              itemBuilder: (context, i) {
                final date = _dateChips[i];
                final selected = date == _selectedDate;
                final hasRecordings = _availableDates.contains(date);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDate = date);
                      _loadDatesAndVideos();
                    },
                    child: Container(
                      width: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFF3B30) : const Color(0xFF1E2330),
                        borderRadius: BorderRadius.circular(8),
                        border: hasRecordings && !selected
                          ? Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3))
                          : null,
                      ),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Center(
                            child: Text(
                              _formatDateChip(date),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: selected ? Colors.white : (hasRecordings ? Colors.white70 : Colors.grey),
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasRecordings && !selected) Positioned(
                            top: 4, right: 6,
                            child: Container(
                              width: 5, height: 5,
                              decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A3040)),

          // Video player area
          if (_loadedVideoUrl != null) SizedBox(
            height: 220,
            child: _PlaybackWebView(
              key: ValueKey('${_loadedVideoUrl}_$_loadedSeekSeconds'),
              playerUrl: _apiService.getPlayerUrl(_loadedVideoUrl!, seekSeconds: _loadedSeekSeconds),
              baseUrl: _apiService.baseUrl,
              token: _apiService.sessionToken,
              onEnded: _onVideoEnded,
              onTimeUpdate: _onTimeUpdate,
            ),
          ),

          // Current video info
          if (_currentVideo != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF161920),
            child: Row(
              children: [
                Text(
                  _currentVideo!.time,
                  style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(_currentVideo!.filename, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _currentVideo!.isH264 ? Colors.blue : Colors.purple,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _currentVideo!.codec.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${_currentVideo!.sizeMb.toStringAsFixed(1)}MB', style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),

          // Timeline
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _cycleZoom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2330),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_zoomLabel, style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final totalWidth = box.size.width - 40; // account for zoom button
                      final ratio = details.localPosition.dx / totalWidth;
                      final totalSeconds = ratio * 86400;
                      _onTimelineTap(totalSeconds);
                    },
                    child: CustomPaint(
                      painter: _TimelinePainter(
                        videos: _videos,
                        events: _events,
                        currentSeconds: _currentPlaySeconds,
                        zoom: _timelineZoom,
                      ),
                      size: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Transcoding indicator
          if (_isTranscoding) Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1E2330),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))),
                SizedBox(width: 8),
                Text('Đang chuyển đổi video...', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),

          // Video list
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _videos.isEmpty
                ? const Center(child: Text('Không có video', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _videos.length,
                    itemBuilder: (context, i) {
                      final video = _videos[i];
                      final isPlaying = i == _currentVideoIndex;
                      return ListTile(
                        dense: true,
                        selected: isPlaying,
                        selectedTileColor: const Color(0xFFFF3B30).withOpacity(0.1),
                        leading: Icon(
                          isPlaying ? Icons.play_circle_filled : Icons.play_circle_outline,
                          color: isPlaying ? const Color(0xFFFF3B30) : Colors.grey,
                          size: 28,
                        ),
                        title: Text(video.time, style: TextStyle(
                          color: isPlaying ? const Color(0xFFFF3B30) : Colors.white,
                          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        )),
                        subtitle: Text(
                          '${_formatDuration(video.duration)} • ${video.sizeMb.toStringAsFixed(1)}MB',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: video.isH264 ? Colors.blue.withOpacity(0.2) : Colors.purple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            video.codec.toUpperCase(),
                            style: TextStyle(
                              color: video.isH264 ? Colors.blue : Colors.purple,
                              fontSize: 9, fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () => _playVideo(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    return '${m}m${s.toString().padLeft(2, '0')}s';
  }
}

// ==================== WEBVIEW PLAYER ====================

class _PlaybackWebView extends StatefulWidget {
  final String playerUrl;
  final String baseUrl;
  final String token;
  final VoidCallback onEnded;
  final ValueChanged<double> onTimeUpdate;

  const _PlaybackWebView({
    super.key,
    required this.playerUrl,
    required this.baseUrl,
    required this.token,
    required this.onEnded,
    required this.onTimeUpdate,
  });

  @override
  State<_PlaybackWebView> createState() => _PlaybackWebViewState();
}

class _PlaybackWebViewState extends State<_PlaybackWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    
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
      ..addJavaScriptChannel('Flutter', onMessageReceived: (msg) {
        if (msg.message == 'ended') {
          widget.onEnded();
        } else if (msg.message.startsWith('time:')) {
          final seconds = double.tryParse(msg.message.substring(5));
          if (seconds != null) widget.onTimeUpdate(seconds);
        }
      });

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
    }

    // Set cookie and load
    final cookieManager = WebViewCookieManager();
    final uri = Uri.parse(widget.baseUrl);
    cookieManager.setCookie(WebViewCookie(
      name: 'dvr_session',
      value: widget.token,
      domain: uri.host,
      path: '/',
    )).then((_) {
      _controller.loadRequest(Uri.parse(widget.playerUrl));
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

// ==================== TIMELINE PAINTER ====================

class _TimelinePainter extends CustomPainter {
  final List<VideoFile> videos;
  final List<Map<String, dynamic>> events;
  final double currentSeconds;
  final int zoom;

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
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(6)),
      bgPaint,
    );

    const totalSeconds = 86400.0;
    double viewStart = 0;
    double viewEnd = totalSeconds;

    if (zoom > 1) {
      final viewDuration = totalSeconds / zoom;
      viewStart = (currentSeconds - viewDuration / 2).clamp(0, totalSeconds - viewDuration);
      viewEnd = viewStart + viewDuration;
    }

    final viewDuration = viewEnd - viewStart;

    // Draw recording blocks
    final recPaint = Paint()..color = Colors.green.withOpacity(0.4);
    for (final v in videos) {
      final start = v.startSeconds.toDouble();
      final end = start + v.duration;
      if (end < viewStart || start > viewEnd) continue;
      final x1 = ((start - viewStart) / viewDuration * size.width).clamp(0.0, size.width);
      final x2 = ((end - viewStart) / viewDuration * size.width).clamp(0.0, size.width);
      canvas.drawRect(Rect.fromLTWH(x1, 8, x2 - x1, size.height - 24), recPaint);
    }

    // Draw event markers
    final eventPaint = Paint()..color = Colors.red.withOpacity(0.7);
    for (final e in events) {
      final ts = e['timestamp'] as String? ?? '';
      final parts = ts.split(' ');
      if (parts.length < 2) continue;
      final timeParts = parts[1].split(':');
      if (timeParts.length < 3) continue;
      final sec = int.parse(timeParts[0]) * 3600 + int.parse(timeParts[1]) * 60 + int.parse(timeParts[2]);
      if (sec < viewStart || sec > viewEnd) continue;
      final x = (sec - viewStart) / viewDuration * size.width;
      canvas.drawCircle(Offset(x, size.height - 12), 3, eventPaint);
    }

    // Draw time ticks
    final tickPaint = Paint()..color = Colors.grey.withOpacity(0.3);
    const textStyle = TextStyle(color: Colors.grey, fontSize: 8);
    int tickInterval;
    if (zoom >= 24) tickInterval = 600; // 10 min
    else if (zoom >= 4) tickInterval = 1800; // 30 min
    else tickInterval = 7200; // 2 hours

    for (int t = 0; t < 86400; t += tickInterval) {
      if (t < viewStart || t > viewEnd) continue;
      final x = (t - viewStart) / viewDuration * size.width;
      canvas.drawLine(Offset(x, size.height - 16), Offset(x, size.height - 8), tickPaint);
      final hour = t ~/ 3600;
      final min = (t % 3600) ~/ 60;
      final label = '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
      final tp = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: ui.TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 6));
    }

    // Draw current position
    if (currentSeconds >= viewStart && currentSeconds <= viewEnd) {
      final x = (currentSeconds - viewStart) / viewDuration * size.width;
      final posPaint = Paint()..color = const Color(0xFFFF3B30)..strokeWidth = 2;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height - 16), posPaint);
      canvas.drawCircle(Offset(x, 4), 4, posPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
    old.currentSeconds != currentSeconds || old.videos != videos || old.zoom != zoom;
}
