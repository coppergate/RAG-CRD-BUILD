import 'package:flutter/material.dart';

class StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final bool isDarkMode;
  final VoidCallback? onDismiss;

  const StatusBanner({
    super.key,
    required this.message,
    required this.isError,
    required this.isDarkMode,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isError ? Colors.red : Colors.green;
    final Color bgColor = isError
        ? (isDarkMode
            ? Colors.red.shade900.withValues(alpha: 0.3)
            : Colors.red.shade50)
        : (isDarkMode
            ? Colors.green.shade900.withValues(alpha: 0.3)
            : Colors.green.shade50);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error : Icons.check_circle,
            color: borderColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: borderColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
