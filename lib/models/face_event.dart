class FaceEvent {
  final String imageUrl;
  final String cameraName;
  final int? cameraId;
  final String timestamp;
  final String? details;

  FaceEvent({
    required this.imageUrl,
    required this.cameraName,
    this.cameraId,
    required this.timestamp,
    this.details,
  });

  factory FaceEvent.fromJson(Map<String, dynamic> json, String baseUrl) {
    String imageUrl = json['url'] as String? ?? json['image_url'] as String? ?? '';
    if (imageUrl.startsWith('/')) {
      imageUrl = '$baseUrl$imageUrl';
    }
    return FaceEvent(
      imageUrl: imageUrl,
      cameraName: json['camera_name'] as String? ?? 'Camera ${json['camera_id'] ?? '?'}',
      cameraId: json['camera_id'] as int?,
      timestamp: json['timestamp'] as String? ?? json['time'] as String? ?? '',
      details: json['details'] as String?,
    );
  }
}
