import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/session.dart';

class SessionDrawer extends StatelessWidget {
  final List<Session> sessions;
  final int? currentSessionId;
  final Set<int> selectedIds;
  final Function(Session, bool) onSelectSession;
  final Function(Session) onDeleteSession;
  final VoidCallback onDeleteSelected;
  final VoidCallback onNewSession;
  final Future<void> Function() onRefresh;

  const SessionDrawer({
    super.key,
    required this.sessions,
    this.currentSessionId,
    required this.selectedIds,
    required this.onSelectSession,
    required this.onDeleteSession,
    required this.onDeleteSelected,
    required this.onNewSession,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add),
              label: const Text('New Session'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
            ),
          ),
          const Divider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isCurrent = session.id == currentSessionId;
                  final isSelected = selectedIds.contains(session.id);
                  
                  return ListTile(
                    leading: Icon(isSelected ? Icons.check_box : Icons.chat_bubble_outline, 
                      color: isSelected ? Colors.blue : null),
                    title: Text(session.name ?? 'Session ${session.id}'),
                    subtitle: Text('Last active: ${_formatTime(session.lastActiveAt)}'),
                    selected: isCurrent || isSelected,
                    onTap: () {
                      final isMultiSelect = HardwareKeyboard.instance.isControlPressed || 
                                          HardwareKeyboard.instance.isMetaPressed;
                      onSelectSession(session, isMultiSelect);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => onDeleteSession(session),
                    ),
                  );
                },
              ),
            ),
          ),
          if (selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: onDeleteSelected,
                icon: const Icon(Icons.delete_sweep),
                label: Text('Delete (${selectedIds.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
