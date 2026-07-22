import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with AutomaticKeepAliveClientMixin {
  final _api = ApiService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  final List<_ChatMessage> _messages = [];

  static const _suggestions = [
    'Hôm nay có ai lạ không?',
    'Hôm qua có ai đến nhà lúc 3 giờ chiều không?',
    'Tuần này có bao nhiêu sự kiện?',
    'Camera nào phát hiện nhiều người nhất?',
    'Có ai về nhà tối qua không?',
  ];

  @override
  bool get wantKeepAlive => true;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final resp = await http.post(
        Uri.parse('${_api.baseUrl}/api/ai/chat'),
        headers: {..._api.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'question': text}),
      ).timeout(const Duration(seconds: 60));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final answer = data['answer'] as String? ?? 'Không có phản hồi.';
        final events = (data['events'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList() ?? [];
        final queryInfo = data['query_info'] as Map<String, dynamic>?;

        setState(() {
          _messages.add(_ChatMessage(
            text: answer,
            isUser: false,
            events: events,
            queryInfo: queryInfo,
          ));
        });
      } else {
        setState(() {
          _messages.add(_ChatMessage(
            text: 'Lỗi: Server trả về ${resp.statusCode}',
            isUser: false,
            isError: true,
          ));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(
          text: 'Không thể kết nối tới server. Kiểm tra lại mạng.',
          isUser: false,
          isError: true,
        ));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              headers: _api.authHeaders,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Camera Chat'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Xóa hội thoại',
              onPressed: () => setState(() => _messages.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: _messages.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_isLoading && i == _messages.length) return _loadingBubble();
                    return _chatBubble(_messages[i]);
                  },
                ),
          ),

          // Input area
          _inputBar(),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.smart_toy_outlined, size: 64, color: Color(0xFF007AFF)),
          const SizedBox(height: 16),
          const Text(
            'Hỏi AI về camera',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Hỏi bằng ngôn ngữ tự nhiên về sự kiện camera, AI sẽ tìm kiếm và trả lời.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _suggestions.map((s) => ActionChip(
              label: Text(s, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              backgroundColor: const Color(0xFF1E2330),
              side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              onPressed: () => _sendMessage(s),
            )).toList(),
          ),
        ],
      ),
    ),
  );

  Widget _chatBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: msg.isError ? Colors.red.withOpacity(0.2) : const Color(0xFF007AFF).withOpacity(0.2),
              child: Icon(
                msg.isError ? Icons.error_outline : Icons.smart_toy,
                size: 18,
                color: msg.isError ? Colors.red : const Color(0xFF007AFF),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF007AFF) : const Color(0xFF1E2330),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: isUser ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: SelectableText(
                    msg.text,
                    style: TextStyle(
                      color: msg.isError ? Colors.red[300] : Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),

                // Query info badge
                if (msg.queryInfo != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      _queryInfoText(msg.queryInfo!),
                      style: TextStyle(color: Colors.grey[600], fontSize: 10),
                    ),
                  ),
                ],

                // Event snapshots
                if (msg.events.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: msg.events.length,
                      itemBuilder: (ctx, i) => _eventThumbnail(msg.events[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF34C759),
              child: Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _queryInfoText(Map<String, dynamic> info) {
    final parts = <String>[];
    if (info['matched_events'] != null) parts.add('${info['matched_events']} sự kiện');
    if (info['date_range'] != null) parts.add('${info['date_range']}');
    if (info['camera'] != null) parts.add('${info['camera']}');
    return parts.isNotEmpty ? '🔍 ${parts.join(' • ')}' : '';
  }

  Widget _eventThumbnail(Map<String, dynamic> event) {
    String imageUrl = event['snapshot_path'] as String? ?? '';
    if (imageUrl.startsWith('/')) imageUrl = '${_api.baseUrl}$imageUrl';
    final time = event['timestamp'] as String? ?? '';
    final camera = event['camera_name'] as String? ?? '';

    return GestureDetector(
      onTap: () => imageUrl.isNotEmpty ? _showFullImage(imageUrl) : null,
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2F3D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      headers: _api.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey, size: 24),
                      ),
                    )
                  : const Center(child: Icon(Icons.image_not_supported, color: Colors.grey, size: 24)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (camera.isNotEmpty)
                    Text(camera, style: const TextStyle(color: Colors.white70, fontSize: 9), overflow: TextOverflow.ellipsis),
                  if (time.isNotEmpty)
                    Text(time.length > 16 ? time.substring(11, 16) : time,
                      style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingBubble() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF007AFF).withOpacity(0.2),
          child: const Icon(Icons.smart_toy, size: 18, color: Color(0xFF007AFF)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2330),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[500]),
              ),
              const SizedBox(width: 10),
              Text('AI đang suy nghĩ...', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _inputBar() => Container(
    padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(
      color: Color(0xFF1E2330),
      border: Border(top: BorderSide(color: Color(0xFF2A2F3D))),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Hỏi về camera...',
              hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
              filled: true,
              fillColor: const Color(0xFF2A2F3D),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: _isLoading ? null : _sendMessage,
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.send_rounded),
          color: const Color(0xFF007AFF),
          onPressed: _isLoading ? null : () => _sendMessage(_controller.text),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final List<Map<String, dynamic>> events;
  final Map<String, dynamic>? queryInfo;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.events = const [],
    this.queryInfo,
  });
}
