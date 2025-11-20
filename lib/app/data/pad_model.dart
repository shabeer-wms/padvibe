class Pad {
  final String name;
  final int? color;
  final String? path;
  final bool isLooping;

  const Pad({
    required this.name,
    this.path,
    this.color = 0xFFB0BEC5, // grey
    this.isLooping = false,
  });

  Pad copyWith({String? name, String? path, int? color, bool? isLooping}) {
    return Pad(
      name: name ?? this.name,
      path: path ?? this.path,
      color: color ?? this.color,
      isLooping: isLooping ?? this.isLooping,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'color': color,
    'isLooping': isLooping,
  };

  factory Pad.fromJson(Map<String, dynamic> json) {
    return Pad(
      name: (json['name'] as String?) ?? 'Pad',
      path: json['path'] as String?,
      color: (json['color'] as int?) ?? 0xFFB0BEC5,
      isLooping: (json['isLooping'] as bool?) ?? false,
    );
  }
}

class PadGroup {
  final String id;
  final String name;
  final List<Pad> pads;

  const PadGroup({required this.id, required this.name, required this.pads});

  PadGroup copyWith({String? id, String? name, List<Pad>? pads}) {
    return PadGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      pads: pads ?? this.pads,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pads': pads.map((p) => p.toJson()).toList(),
  };

  factory PadGroup.fromJson(Map<String, dynamic> json) {
    return PadGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      pads: (json['pads'] as List)
          .map((e) => Pad.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
