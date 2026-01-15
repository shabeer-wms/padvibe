class Pad {
  final String name;
  final int? color;
  final String? path;
  final bool isLooping;
  final String? keyboardShortcut;
  final int? midiNote;
  final int? deviceId; // Added for audio routing
  final List<int>? outputChannels; // Added for channel routing
  final String filterType; // 'none', 'lowpass', 'highpass'
  final double filterFrequency;

  const Pad({
    required this.name,
    this.path,
    this.color = 0xFFB0BEC5, // grey
    this.isLooping = false,
    this.keyboardShortcut,
    this.midiNote,
    this.deviceId,
    this.outputChannels,
    this.filterType = 'none',
    this.filterFrequency = 20000.0,
  });

  Pad copyWith({
    String? name,
    String? path,
    int? color,
    bool? isLooping,
    String? keyboardShortcut,
    int? midiNote,
    int? deviceId,
    List<int>? outputChannels,
    String? filterType,
    double? filterFrequency,
    bool clearPath = false,
    bool clearDeviceId = false,
    bool clearOutputChannels = false,
    bool clearKeyboardShortcut = false,
    bool clearMidiNote = false,
  }) {
    return Pad(
      name: name ?? this.name,
      path: clearPath ? null : (path ?? this.path),
      color: color ?? this.color,
      isLooping: isLooping ?? this.isLooping,
      keyboardShortcut:
          clearKeyboardShortcut ? null : (keyboardShortcut ?? this.keyboardShortcut),
      midiNote: clearMidiNote ? null : (midiNote ?? this.midiNote),
      deviceId: clearDeviceId ? null : (deviceId ?? this.deviceId),
      outputChannels:
          clearOutputChannels ? null : (outputChannels ?? this.outputChannels),
      filterType: filterType ?? this.filterType,
      filterFrequency: filterFrequency ?? this.filterFrequency,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'color': color,
        'isLooping': isLooping,
        'keyboardShortcut': keyboardShortcut,
        'midiNote': midiNote,
        'deviceId': deviceId,
        'outputChannels': outputChannels,
        'filterType': filterType,
        'filterFrequency': filterFrequency,
      };

  factory Pad.fromJson(Map<String, dynamic> json) {
    return Pad(
      name: (json['name'] as String?) ?? 'Pad',
      path: json['path'] as String?,
      color: (json['color'] as int?) ?? 0xFFB0BEC5,
      isLooping: (json['isLooping'] as bool?) ?? false,
      keyboardShortcut: json['keyboardShortcut'] as String?,
      midiNote: json['midiNote'] as int?,
      deviceId: json['deviceId'] as int?,
      outputChannels: (json['outputChannels'] as List?)?.cast<int>(),
      filterType: (json['filterType'] as String?) ?? 'none',
      filterFrequency: (json['filterFrequency'] as num?)?.toDouble() ?? 20000.0,
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
