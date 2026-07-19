
class PoseChunkMeta {
  const PoseChunkMeta({
    required this.frameCount,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.durationMs,
    required this.chunks,
    this.schemaVersion,
    this.capture,
    this.device,
    this.captureParams,
  });

  final String? schemaVersion;
  final int frameCount;
  final int startTimestampMs;
  final int endTimestampMs;
  final int durationMs;
  final List<PoseChunkInfo> chunks;
  final Map<String, dynamic>? capture;
  final Map<String, dynamic>? device;
  final Map<String, dynamic>? captureParams;

  factory PoseChunkMeta.fromJson(Map<String, dynamic> json) {
    final rawChunks = json['chunks'] as List<dynamic>? ?? [];
    return PoseChunkMeta(
      schemaVersion: json['schemaVersion'] as String?,
      frameCount: json['frameCount'] as int? ?? 0,
      startTimestampMs: json['startTimestampMs'] as int? ?? 0,
      endTimestampMs: json['endTimestampMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      chunks: rawChunks
          .map((e) => PoseChunkInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      capture: json['capture'] as Map<String, dynamic>?,
      device: json['device'] as Map<String, dynamic>?,
      captureParams: json['captureParams'] as Map<String, dynamic>?,
    );
  }

  
  int chunkIndexForTime(int timeMs) {
    if (chunks.isEmpty) return 0;
    if (timeMs <= chunks.first.startTimestampMs) return chunks.first.index;
    if (timeMs >= chunks.last.endTimestampMs) return chunks.last.index;
    for (final c in chunks) {
      if (timeMs >= c.startTimestampMs && timeMs <= c.endTimestampMs) {
        return c.index;
      }
      
      if (timeMs < c.startTimestampMs) return c.index;
    }
    return chunks.last.index;
  }
}

class PoseChunkInfo {
  const PoseChunkInfo({
    required this.index,
    required this.asset,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.frameCount,
    this.frameStartIndex = 0,
  });

  final int index;
  final String asset;
  final int startTimestampMs;
  final int endTimestampMs;
  final int frameCount;
  final int frameStartIndex;

  factory PoseChunkInfo.fromJson(Map<String, dynamic> json) {
    return PoseChunkInfo(
      index: json['index'] as int,
      asset: json['asset'] as String,
      startTimestampMs: json['startTimestampMs'] as int,
      endTimestampMs: json['endTimestampMs'] as int,
      frameCount: json['frameCount'] as int? ?? 0,
      frameStartIndex: json['frameStartIndex'] as int? ?? 0,
    );
  }
}
