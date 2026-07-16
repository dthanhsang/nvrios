import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/camera.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<Camera> _cameras = [];
  bool _isLoading = true;
  int _columns = 1;
  final Map<int, GlobalKey<_MjpegStreamPlayerState>> _streamKeys = {};

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
        for (final cam in _cameras) {
          _streamKeys.putIfAbsent(cam.id, () => GlobalKey<_MjpegStreamPlayerState>());
        }
        _isLoading = false;
      });
    }
  }

  void _openFullscreen(Camera camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenLiveView(camera: camera, apiService: _apiService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trực tiếp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            color: _columns == 2 ? const Color(0xFFFF3B30) : Colors.grey,
            onPressed: () => setState(() => _columns = _columns == 1 ? 2 : 1),
            tooltip: 'Đổi bố cục',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCameras,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _cameras.isEmpty
          ? const Center(child: Text('Không có camera nào', style: TextStyle(color: Colors.grey)))
          : RefreshIndicator(
              onRefresh: _loadCameras,
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 16 / 10,
                ),
                itemCount: _cameras.length,
                itemBuilder: (context, index) {
                  final camera = _cameras[index];
                  return _CameraTile(
                    camera: camera,
                    streamKey: _streamKeys[camera.id]!,
                    apiService: _apiService,
                    onFullscreen: () => _openFullscreen(camera),
                  );
                },
              ),
            ),
    );
  }
}

class _CameraTile extends StatelessWidget {
  final Camera camera;
  final GlobalKey<_MjpegStreamPlayerState> streamKey;
  final ApiService apiService;
  final VoidCallback onFullscreen;

  const _CameraTile({
    required this.camera,
    required this.streamKey,
    required this.apiService,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final streamUrl = apiService.getMjpegStreamUrl(camera.go2rtcSrc);
    return GestureDetector(
      onTap: onFullscreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            MjpegStreamPlayer(
              key: streamKey,
              streamUrl: streamUrl,
            ),
            // Camera name overlay
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        camera.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.white, size: 6),
                          SizedBox(width: 4),
                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Fullscreen button
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: onFullscreen,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== FULLSCREEN LIVE VIEW ====================

class _FullscreenLiveView extends StatefulWidget {
  final Camera camera;
  final ApiService apiService;

  const _FullscreenLiveView({required this.camera, required this.apiService});

  @override
  State<_FullscreenLiveView> createState() => _FullscreenLiveViewState();
}

class _FullscreenLiveViewState extends State<_FullscreenLiveView> {
  bool _showControls = true;
  bool _isHd = true;
  Timer? _hideTimer;
  final _streamKey = GlobalKey<_MjpegStreamPlayerState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _toggleQuality() {
    setState(() => _isHd = !_isHd);
    _startHideTimer();
  }

  String get _currentStreamUrl {
    return widget.apiService.getMjpegStreamUrl(widget.camera.go2rtcSrc, hd: _isHd);
  }

  void _captureScreenshot() {
    final state = _streamKey.currentState;
    if (state != null && state._currentFrame != null) {
      // Save frame to gallery
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã chụp ảnh màn hình')),
      );
    }
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Stream with pinch-to-zoom
              InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: MjpegStreamPlayer(
                    key: _streamKey,
                    streamUrl: _currentStreamUrl,
                  ),
                ),
              ),
              // Top bar
              Positioned(
                top: 0, left: 0, right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.camera.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3B30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, color: Colors.white, size: 6),
                                    SizedBox(width: 4),
                                    Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _toggleQuality,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _isHd ? const Color(0xFFFF3B30) : Colors.white24,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _isHd ? 'HD' : 'SD',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom bar
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ControlButton(icon: Icons.camera_alt, label: 'Chụp', onTap: _captureScreenshot),
                            const SizedBox(width: 32),
                            _ControlButton(icon: Icons.replay, label: 'Xem lại', onTap: () {
                              Navigator.pop(context);
                              // TODO: navigate to playback for this camera
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

// ==================== MJPEG STREAM PLAYER ====================

class MjpegStreamPlayer extends StatefulWidget {
  final String streamUrl;

  const MjpegStreamPlayer({super.key, required this.streamUrl});

  @override
  State<MjpegStreamPlayer> createState() => _MjpegStreamPlayerState();
}

class _MjpegStreamPlayerState extends State<MjpegStreamPlayer> with AutomaticKeepAliveClientMixin {
  Uint8List? _currentFrame;
  bool _isConnecting = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  static const int _maxRetries = 5;
  HttpClient? _httpClient;
  bool _disposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(MjpegStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _disconnect();
      _retryCount = 0;
      _connect();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnect();
    super.dispose();
  }

  void _disconnect() {
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  Future<void> _connect() async {
    if (_disposed) return;
    setState(() { _isConnecting = true; _hasError = false; });

    try {
      _httpClient?.close(force: true);
      _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..badCertificateCallback = (cert, host, port) => true;

      final uri = Uri.parse(widget.streamUrl);
      final request = await _httpClient!.getUrl(uri);
      request.headers.set('Connection', 'keep-alive');
      final response = await request.close();

      if (_disposed) return;
      setState(() => _isConnecting = false);

      // Parse multipart MJPEG stream
      List<int> buffer = [];
      int? contentLength;

      await for (final chunk in response) {
        if (_disposed) break;
        buffer.addAll(chunk);

        while (buffer.length > 2) {
          if (contentLength == null) {
            // Look for Content-Length header
            final headerEnd = _findHeaderEnd(buffer);
            if (headerEnd == -1) {
              if (buffer.length > 4000) buffer = buffer.sublist(buffer.length - 2000);
              break;
            }
            final headerStr = String.fromCharCodes(buffer.sublist(0, headerEnd));
            contentLength = _parseContentLength(headerStr);
            buffer = buffer.sublist(headerEnd);
            if (contentLength == null || contentLength <= 0 || contentLength > 5 * 1024 * 1024) {
              contentLength = null;
              continue;
            }
          }

          if (contentLength != null && buffer.length >= contentLength) {
            final frameData = Uint8List.fromList(buffer.sublist(0, contentLength));
            buffer = buffer.sublist(contentLength);
            contentLength = null;

            // Validate JPEG SOI marker
            if (frameData.length > 2 && frameData[0] == 0xFF && frameData[1] == 0xD8) {
              if (!_disposed && mounted) {
                setState(() {
                  _currentFrame = frameData;
                  _retryCount = 0;
                });
              }
            }
          } else {
            break;
          }
        }
      }

      // Stream ended
      if (!_disposed) _retry();
    } catch (e) {
      if (!_disposed) {
        setState(() {
          _isConnecting = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
        _retry();
      }
    }
  }

  int _findHeaderEnd(List<int> buffer) {
    for (int i = 0; i < buffer.length - 3; i++) {
      if (buffer[i] == 0x0D && buffer[i + 1] == 0x0A && buffer[i + 2] == 0x0D && buffer[i + 3] == 0x0A) {
        return i + 4;
      }
    }
    return -1;
  }

  int? _parseContentLength(String header) {
    final lines = header.split('\n');
    for (final line in lines) {
      final lower = line.toLowerCase().trim();
      if (lower.startsWith('content-length:')) {
        return int.tryParse(lower.split(':').last.trim());
      }
    }
    return null;
  }

  void _retry() {
    if (_disposed || _retryCount >= _maxRetries) return;
    _retryCount++;
    Future.delayed(Duration(seconds: _retryCount.clamp(1, 5)), () {
      if (!_disposed) _connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_currentFrame != null) {
      return Image.memory(
        _currentFrame!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))),
            SizedBox(height: 8),
            Text('Đang kết nối...', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      );
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_off, color: Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(
              _retryCount >= _maxRetries ? 'Không thể kết nối' : 'Đang thử lại... ($_retryCount/$_maxRetries)',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            if (_retryCount >= _maxRetries)
              TextButton(
                onPressed: () { _retryCount = 0; _connect(); },
                child: const Text('Thử lại', style: TextStyle(color: Color(0xFFFF3B30))),
              ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
