import 'package:flutter/material.dart';
import '../../../core/models/session.dart';

class SessionList extends StatelessWidget {
  final List<Session> sessions;
  final Session? selectedSession;
  final Function(Session) onSelect;

  const SessionList({
    super.key,
    required this.sessions,
    this.selectedSession,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(child: Text('No sessions found.'));
    }

    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final s = sessions[index];
        return ListTile(
          title: Text(s.name ?? 'Session ${s.id}'),
          subtitle: Text('ID: ${s.id}'),
          selected: selectedSession?.id == s.id,
          onTap: () => onSelect(s),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }
}
