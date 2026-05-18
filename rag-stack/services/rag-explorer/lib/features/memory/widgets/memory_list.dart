import 'package:flutter/material.dart';

class MemoryList extends StatelessWidget {
  final List<dynamic> items;

  const MemoryList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No memory items found for this session.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index] as Map<String, dynamic>;
        final content = item['content'] ?? '';
        final salience = (item['salience'] as num?)?.toDouble() ?? 0.0;
        final timestamp = item['timestamp'] ?? '';
        
        return Card(
          child: ListTile(
            title: Text(content),
            subtitle: Text('Salience: ${salience.toStringAsFixed(2)} | Time: ${timestamp.toString().split('T')[0]}'),
            leading: Icon(
              salience > 0.5 ? Icons.star : Icons.history,
              color: salience > 0.5 ? Colors.orange : Colors.blue,
            ),
          ),
        );
      },
    );
  }
}
