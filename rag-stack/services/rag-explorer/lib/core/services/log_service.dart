import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String level;
  final String? location;

  LogEntry({required this.timestamp, required this.message, this.level = 'INFO', this.location});

  @override
  String toString() {
    final timeStr = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}";
    final locStr = location != null ? ' [$location]' : '';
    return '[$timeStr] $level$locStr: $message';
  }
}

class LogNotifier extends StateNotifier<List<LogEntry>> {
  LogNotifier() : super([]);

  String _extractLocation() {
    if (!kDebugMode && !kProfileMode) {
      return 'release';
    }
    
    try {
      final stack = StackTrace.current.toString().split('\n');
      // Find the first frame that is NOT in this file
      for (var frame in stack) {
        if (frame.isEmpty) continue;
        // Skip the frames from this service
        if (frame.contains('log_service.dart')) continue;
        
        // Extract what's inside parentheses if it exists
        final match = RegExp(r'\((.+)\)').firstMatch(frame);
        if (match != null) {
          String loc = match.group(1)!;
          // Simplify if it's a package path
          loc = loc.replaceAll('package:rag_explorer/', '');
          return loc;
        }
        
        // Fallback: take the last part of the frame string
        final parts = frame.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          return parts.last;
        }
      }
    } catch (e) {
      // Silently fail if stack trace parsing fails
    }
    return 'unknown';
  }

  void log(String message, {String level = 'INFO'}) {
    final location = _extractLocation();
    final entry = LogEntry(timestamp: DateTime.now(), message: message, level: level, location: location);
    
    // Also print to console immediately
    print(entry.toString());

    // Update state in a microtask to avoid "modifying provider during build" errors
    // This is especially important for logging which might be triggered during
    // widget lifecycles like initState or build.
    Future.microtask(() {
      state = [...state, entry];
      // Keep last 500 logs for better history in UI
      if (state.length > 500) {
        state = state.sublist(state.length - 500);
      }
    });
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
