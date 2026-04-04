import 'package:flutter_riverpod/flutter_riverpod.dart';

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String level;

  LogEntry({required this.timestamp, required this.message, this.level = 'INFO'});

  @override
  String toString() {
    final timeStr = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}";
    return '[$timeStr] $level: $message';
  }
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  LogNotifier() : super([]);

  void log(String message, {String level = 'INFO'}) {
    final entry = LogEntry(timestamp: DateTime.now(), message: message, level: level);
    state = [...state, entry];
    // Keep last 500 logs for better history in UI
    if (state.length > 500) {
      state = state.sublist(state.length - 500);
    }
    // Also print to console
    print(entry.toString());
  }

  void info(String message) => log(message, level: 'INFO');
  void error(String message) => log(message, level: 'ERROR');
  void warn(String message) => log(message, level: 'WARN');
  void debug(String message) => log(message, level: 'DEBUG');
  
  void clear() => state = [];
}

final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});
