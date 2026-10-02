import 'parse_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';

class TorrentFile {
  final int index;
  final String name;
  final int size;
  final double progress;
  final int priority;

  const TorrentFile({
    required this.index,
    required this.name,
    required this.size,
    required this.progress,
    required this.priority,
  });

  factory TorrentFile.fromJson(Map<String, dynamic> json) {
    return TorrentFile(
      index: parseInt(json['index'] ?? json['id']),
      name: json['name'] as String? ?? '',
      size: parseInt(json['size']),
      progress: parseDouble(json['progress']),
      priority: parseInt(json['priority']),
    );
  }

  String get sizeFormatted => formatSize(size);

  String get progressFormatted => formatPercent(progress * 100, decimals: 1);

  String get priorityLabel => switch (priority) {
    0 => 'Do not download',
    1 => 'Normal',
    2 => 'High',
    6 => 'Maximum',
    7 => 'Mixed',
    _ => 'Priority $priority',
  };
}
