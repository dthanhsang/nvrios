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

    int? parsedCameraId;
    if (json['camera_id'] != null) {
      if (json['camera_id'] is int) {
        parsedCameraId = json['camera_id'] as int;
      } else {
        parsedCameraId = int.tryParse(json['camera_id'].toString());
      }
    }

    String timestamp = json['timestamp'] as String? ?? '';
    if (timestamp.isEmpty && json['date'] != null && json['time'] != null) {
      timestamp = '${json['date']} ${json['time']}';
    } else if (timestamp.isEmpty) {
      timestamp = json['time'] as String? ?? '';
    }

    return FaceEvent(
      imageUrl: imageUrl,
      cameraName: json['camera_name'] as String? ?? 'Camera ${json['camera_id'] ?? '?'}',
      cameraId: parsedCameraId,
      timestamp: timestamp,
      details: json['details'] as String?,
    );
  }
}
