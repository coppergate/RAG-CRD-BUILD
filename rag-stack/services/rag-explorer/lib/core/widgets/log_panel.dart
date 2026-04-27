import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/log_service.dart';
import '../../app_config_provider.dart';

class LogPanel extends ConsumerStatefulWidget {
  final double width;
  final VoidCallback onClear;

  const LogPanel({
    super.key,
    required this.width,
    required this.onClear,
  });

  @override
  ConsumerState<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends ConsumerState<LogPanel> {
  final ScrollController _logScrollController = ScrollController();
  bool _isLogSelected = false;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logProvider);
    final darkMode = ref.watch(appConfigProvider).darkMode;
    
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients && !_isLogSelected) {
        _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
      }
    });

    return SizedBox(
      width: widget.width,
      child: SelectionArea(
        onSelectionChanged: (content) {
          final isSelected = content != null && content.plainText.isNotEmpty;
          if (isSelected != _isLogSelected) {
            setState(() {
              _isLogSelected = isSelected;
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('System Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    onPressed: widget.onClear,
                    tooltip: 'Clear Logs',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: darkMode ? Colors.white.withValues(alpha: .05) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  controller: _logScrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    Color color = darkMode ? Colors.white : Colors.black87;
                    if (log.level == 'ERROR') color = darkMode ? Colors.redAccent : Colors.red;
                    if (log.level == 'WARN') color = darkMode ? Colors.yellowAccent : Colors.orange[800]!;
                    if (log.level == 'DEBUG') color = darkMode ? const Color.fromARGB(255, 237, 196, 250) : Colors.blue[800]!;
  
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        log.toString(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: color,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
