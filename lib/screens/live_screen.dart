import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/camera.dart';

// ==================== GRID CELL MODEL ====================

/// Represents one cell in the grid layout.
/// Each cell can have an assigned camera and an HD/SD toggle.
class _GridCell {
  Camera? camera;
  bool isHd;
  GlobalKey<_MjpegStreamPlayerState> streamKey;

  _GridCell({this.camera, this.isHd = false})
      : streamKey = GlobalKey<_MjpegStreamPlayerState>();
}

// ==================== LIVE SCREEN ====================

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<Camera> _cameras = [];
  bool _isLoading = true;

  /// Current grid size: 1 = 1x1, 2 = 2x2, 3 = 3x3
  int _gridSize = 1;

  /// Grid cells — length = _gridSize * _gridSize
  List<_GridCell> _cells = [];

  /// Currently selected cell index (for camera assignment)
  int? _selectedCellIndex;

  int _currentPageIndex = 0;
  final PageController _pageController = PageController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initCells();
    _loadCameras();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Initialize cells for the current grid size.
  void _initCells() {
    if (_gridSize == 1) {
      _cells = [_GridCell(isHd: true)];
    } else {
      final count = _gridSize * _gridSize;
      _cells = List.generate(count, (_) => _GridCell());
    }
  }

  /// Change grid size, preserving existing camera assignments where possible.
  void _setGridSize(int size) {
    if (size == _gridSize) return;
    _gridSize = size;
    _selectedCellIndex = null;
    _currentPageIndex = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    if (_gridSize == 1) {
      if (_cameras.isEmpty) {
        _cells = [_GridCell(isHd: true)];
      } else {
        _cells = List.generate(_cameras.length, (i) => _GridCell(camera: _cameras[i], isHd: true));
      }
    } else {
      final newCount = size * size;
      _cells = List.generate(newCount, (i) {
        final cam = (i < _cameras.length) ? _cameras[i] : null;
        return _GridCell(camera: cam, isHd: false);
      });
    }

    setState(() {});
  }

  /// Auto-assign cameras to empty grid cells.
  void _autoAssignCameras() {
    final autoHd = _gridSize == 1;
    if (_gridSize == 1) {
      if (_cameras.isEmpty) {
        _cells = [_GridCell(isHd: true)];
      } else {
        _cells = List.generate(_cameras.length, (i) => _GridCell(camera: _cameras[i], isHd: true));
      }
    } else {
      int cameraIdx = 0;
      for (int i = 0; i < _cells.length && cameraIdx < _cameras.length; i++) {
        if (_cells[i].camera == null) {
          _cells[i] = _GridCell(camera: _cameras[cameraIdx], isHd: autoHd);
          cameraIdx++;
        } else {
          // Skip cameras already assigned
          cameraIdx++;
        }
      }
    }
    setState(() {});
  }

  Future<void> _loadCameras() async {
    final cameras = await _apiService.getCameras();
    if (mounted) {
      setState(() {
        _cameras = cameras.where((c) => c.enabled).toList();
        _isLoading = false;
      });
      // Auto-assign cameras to grid cells
      _autoAssignCameras();
    }
  }

  /// Open fullscreen for a camera (double-tap).
  void _openFullscreen(Camera camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenLiveView(camera: camera, apiService: _apiService),
      ),
    );
  }

  /// Show camera picker drawer for the selected cell.
  void _showCameraPicker(int cellIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Chọn camera',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              // "None" option to clear the cell
              ListTile(
                leading: const Icon(Icons.clear, color: Colors.grey),
                title: const Text('Bỏ chọn', style: TextStyle(color: Colors.grey)),
                onTap: () {
                  setState(() {
                    _cells[cellIndex] = _GridCell(isHd: _gridSize == 1);
                    _selectedCellIndex = null;
                  });
                  Navigator.pop(ctx);
                },
              ),
              const Divider(color: Colors.grey, height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _cameras.length,
                  itemBuilder: (_, i) {
                    final cam = _cameras[i];
                    // Check if this camera is already assigned to another cell
                    final alreadyUsed = _cells.any((c) => c.camera?.id == cam.id);
                    return ListTile(
                      leading: Icon(
                        Icons.videocam,
                        color: alreadyUsed ? Colors.grey : const Color(0xFFFF3B30),
                      ),
                      title: Text(
                        cam.name,
                        style: TextStyle(
                          color: alreadyUsed ? Colors.grey : Colors.white,
                        ),
                      ),
                      subtitle: alreadyUsed
                          ? const Text('Đang sử dụng', style: TextStyle(color: Colors.grey, fontSize: 11))
                          : null,
                      onTap: () {
                        setState(() {
                          _cells[cellIndex] = _GridCell(
                            camera: cam,
                            isHd: _gridSize == 1,
                          );
                          _selectedCellIndex = null;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Snapshot placeholder for a cell.
  void _captureSnapshot(int cellIndex) {
    final cell = _cells[cellIndex];
    if (cell.camera == null) return;
    final state = cell.streamKey.currentState;
    if (state != null && state._currentFrame != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã chụp: ${cell.camera!.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có khung hình để chụp'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Trực tiếp'),
        backgroundColor: const Color(0xFF1C1C1E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCameras,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : _cameras.isEmpty
              ? const Center(
                  child: Text('Không có camera nào',
                      style: TextStyle(color: Colors.grey)))
              : Column(
                  children: [
                    // Grid area
                    Expanded(child: _buildGrid()),
                    // Bottom toolbar with grid selector
                    _buildBottomToolbar(),
                  ],
                ),
    );
  }

  Widget _buildGrid() {
    if (_gridSize == 1) {
      return ListView.builder(
        itemCount: _cells.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: _buildGridCell(index),
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridSize,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
          childAspectRatio: 16 / 10,
        ),
        itemCount: _cells.length,
        itemBuilder: (context, index) {
          return _buildGridCell(index);
        },
      ),
    );
  }

  Widget _buildGridCell(int index) {
    final cell = _cells[index];
    final isSelected = _selectedCellIndex == index;

    return GestureDetector(
      // Single tap to select cell
      onTap: () {
        if (cell.camera != null) {
          setState(() {
            if (isSelected) {
              _selectedCellIndex = null;
              cell.isHd = _gridSize == 1;
            } else {
              for (int i = 0; i < _cells.length; i++) {
                _cells[i].isHd = (_gridSize == 1) || (i == index);
              }
              _selectedCellIndex = index;
            }
          });
        } else {
          // No camera assigned — open picker immediately
          _showCameraPicker(index);
        }
      },
      // Double tap to go fullscreen
      onDoubleTap: () {
        if (cell.camera != null) {
          _openFullscreen(cell.camera!);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF3B30) : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF1C1C1E)),
              if (cell.camera != null) ...[
                // MJPEG stream
                MjpegStreamPlayer(
                  key: cell.streamKey,
                  streamUrl: _apiService.getMjpegStreamUrl(
                    cell.camera!.go2rtcSrc,
                    hd: cell.isHd,
                  ),
                ),
                // Camera name overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            cell.camera!.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _gridSize == 1 ? 13 : 10,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // LIVE badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, color: Colors.white, size: 4),
                              const SizedBox(width: 2),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: _gridSize == 1 ? 9 : 7,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // HD/SD badge (top-left)
                Positioned(
                  top: 4,
                  left: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        cell.isHd = !cell.isHd;
                        // Force stream key refresh
                        _cells[index] = _GridCell(
                          camera: cell.camera,
                          isHd: cell.isHd,
                        );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: cell.isHd ? const Color(0xFFFF3B30) : Colors.black54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        cell.isHd ? 'HD' : 'SD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _gridSize == 1 ? 10 : 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                // Cell action buttons (when selected)
                if (isSelected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Snapshot button
                        _CellActionButton(
                          icon: Icons.camera_alt,
                          onTap: () => _captureSnapshot(index),
                          size: _gridSize == 1 ? 28 : 22,
                        ),
                        const SizedBox(width: 4),
                        // Fullscreen button
                        _CellActionButton(
                          icon: Icons.fullscreen,
                          onTap: () => _openFullscreen(cell.camera!),
                          size: _gridSize == 1 ? 28 : 22,
                        ),
                        const SizedBox(width: 4),
                        // Change camera button
                        _CellActionButton(
                          icon: Icons.swap_horiz,
                          onTap: () => _showCameraPicker(index),
                          size: _gridSize == 1 ? 28 : 22,
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                // Empty cell — tap to assign camera
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        color: Colors.grey[600],
                        size: _gridSize == 1 ? 48 : 28,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chọn camera',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: _gridSize == 1 ? 13 : 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GridSizeButton(
              label: '1×1',
              icon: Icons.crop_square,
              isActive: _gridSize == 1,
              onTap: () => _setGridSize(1),
            ),
            const SizedBox(width: 16),
            _GridSizeButton(
              label: '2×2',
              icon: Icons.grid_view,
              isActive: _gridSize == 2,
              onTap: () => _setGridSize(2),
            ),
            const SizedBox(width: 16),
            _GridSizeButton(
              label: '3×3',
              icon: Icons.apps,
              isActive: _gridSize == 3,
              onTap: () => _setGridSize(3),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== SMALL UI COMPONENTS ====================

class _CellActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _CellActionButton({
    required this.icon,
    required this.onTap,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.6),
      ),
    );
  }
}

class _GridSizeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _GridSizeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFF3B30) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
  int _connectProgress = 0;
  // ignore: unused_field
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
    setState(() {
      _connectProgress = 10;
      _isConnecting = true;
      _hasError = false;
    });

    try {
      _httpClient?.close(force: true);
      _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..badCertificateCallback = (cert, host, port) => true;

      final uri = Uri.parse(widget.streamUrl);
      if (mounted) setState(() => _connectProgress = 30);
      final request = await _httpClient!.getUrl(uri);
      request.headers.set('Connection', 'keep-alive');
      
      if (mounted) setState(() => _connectProgress = 50);
      final response = await request.close();

      if (_disposed) return;
      if (mounted) setState(() => _connectProgress = 70);

      // Parse multipart MJPEG stream using SOI (0xFFD8) and EOI (0xFFD9) markers
      // with memory optimizations (BytesBuilder & zero-copy Uint8List views)
      // to reduce GC pressure and CPU overhead on iOS devices.
      final builder = BytesBuilder(copy: false);
      bool receivedFirstChunk = false;

      await for (final chunk in response) {
        if (_disposed) break;
        if (!receivedFirstChunk) {
          receivedFirstChunk = true;
          if (mounted) setState(() => _connectProgress = 90);
        }
        builder.add(chunk);

        Uint8List buffer = builder.takeBytes();

        while (buffer.length > 4) {
          // Find JPEG Start of Image (SOI) marker
          int startIdx = -1;
          for (int i = 0; i < buffer.length - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
              startIdx = i;
              break;
            }
          }

          if (startIdx == -1) {
            // Clear old buffer data if no start marker is found to prevent memory leaks
            if (buffer.length > 8192) {
              buffer = buffer.sublist(buffer.length - 1024);
            }
            break;
          }

          // Find JPEG End of Image (EOI) marker
          int endIdx = -1;
          for (int i = startIdx + 2; i < buffer.length - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
              endIdx = i + 2;
              break;
            }
          }

          if (endIdx != -1) {
            // Use zero-copy sublistView to feed image directly to rendering memory
            final frameData = Uint8List.sublistView(buffer, startIdx, endIdx);
            buffer = buffer.sublist(endIdx);

            if (!_disposed && mounted) {
              setState(() {
                _currentFrame = frameData;
                _isConnecting = false;
                _retryCount = 0;
              });
            }
          } else {
            // Start marker found but end marker not received yet, wait for more chunks.
            // Clear if buffer gets ridiculously large without EOI
            if (buffer.length > 5 * 1024 * 1024) {
              buffer = Uint8List(0);
            }
            break;
          }
        }

        if (buffer.isNotEmpty) {
          builder.add(buffer);
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
    if (_isConnecting || (_currentFrame == null && !_hasError)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B30))),
            const SizedBox(height: 8),
            Text('Đang kết nối... $_connectProgress%', style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
