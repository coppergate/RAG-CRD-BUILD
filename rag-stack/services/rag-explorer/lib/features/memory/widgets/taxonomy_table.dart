import 'package:flutter/material.dart';

class TaxonomyTable extends StatelessWidget {
  final List<String> identifiers;

  const TaxonomyTable({super.key, required this.identifiers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Action Taxonomy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Valid identifiers for REMEMBER syntax:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DataTable(
            headingRowHeight: 32,
            columns: const [DataColumn(label: Text('Identifier'))],
            rows: identifiers.map((e) => DataRow(cells: [DataCell(Text(e))])).toList(),
          ),
        ),
      ],
    );
  }
}
