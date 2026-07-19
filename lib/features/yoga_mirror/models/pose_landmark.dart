class PoseLandmark {
  const PoseLandmark({
    required this.index,
    required this.name,
    required this.x,
    required this.y,
    this.xNorm,
    this.yNorm,
    this.z = 0,
    this.wx,
    this.wy,
    this.wz,
    this.visibility = 1,
    this.presence = 1,
  });

  final int index;
  final String name;
  final double x;
  final double y;
  final double? xNorm;
  final double? yNorm;
  final double z;
  final double? wx;
  final double? wy;
  final double? wz;
  final double visibility;
  final double presence;

  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      index: json['index'] as int,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      xNorm: (json['xNorm'] as num?)?.toDouble(),
      yNorm: (json['yNorm'] as num?)?.toDouble(),
      z: (json['z'] as num?)?.toDouble() ?? 0,
      wx: (json['wx'] as num?)?.toDouble(),
      wy: (json['wy'] as num?)?.toDouble(),
      wz: (json['wz'] as num?)?.toDouble(),
      visibility: (json['visibility'] as num?)?.toDouble() ?? 1,
      presence: (json['presence'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'x': x,
        'y': y,
        if (xNorm != null) 'xNorm': xNorm,
        if (yNorm != null) 'yNorm': yNorm,
        'z': z,
        if (wx != null) 'wx': wx,
        if (wy != null) 'wy': wy,
        if (wz != null) 'wz': wz,
        'visibility': visibility,
        'presence': presence,
      };

  
  double normalizedX(double frameWidth) =>
      xNorm ?? (frameWidth > 0 ? x / frameWidth : x);

  double normalizedY(double frameHeight) =>
      yNorm ?? (frameHeight > 0 ? y / frameHeight : y);
}