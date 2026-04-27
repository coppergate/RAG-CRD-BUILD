import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/service_endpoints.dart';
import '../../core/api_client.dart';
import '../../core/models/metrics.dart';
import '../../core/models/tag.dart';
import '../../core/models/session.dart';

class S3Page extends StatefulWidget {
  const S3Page({super.key});

  @override
  State<S3Page> createState() => _S3PageState();
}

class _S3PageState extends State<S3Page> {
  late Future<List<VirtualFile>> _filesFuture;
  Tag? _selectedTag;
  Session? _selectedSession;
  late Future<List<Tag>> _tagsFuture;
  late Future<List<Session>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _fetchFiles();
    _tagsFuture = _fetchTags();
    _sessionsFuture = _fetchSessions();
  }

  Future<List<VirtualFile>> _fetchFiles() async {
    final config = context.read<AppConfigProvider>().config;
    final client = ApiClient(config);
    Map<String, dynamic> queryParams = {};
    if (_selectedTag != null) queryParams['tag_id'] = _selectedTag!.id;
    if (_selectedSession != null) queryParams['session_id'] = _selectedSession!.id;
    
    final response = await client.get('${ServiceEndpoints.dbAdapter}/storage/files', queryParameters: queryParams);
    return (response.data as List).map((e) => VirtualFile.fromJson(e)).toList();
  }

  Future<List<Tag>> _fetchTags() async {
    final config = context.read<AppConfigProvider>().config;
    final client = ApiClient(config);
    final response = await client.get('${ServiceEndpoints.dbAdapter}/tags');
    return (response.data as List).map((e) => Tag.fromJson(e)).toList();
  }

  Future<List<Session>> _fetchSessions() async {
    final config = context.read<AppConfigProvider>().config;
    final client = ApiClient(config);
    final response = await client.get('${ServiceEndpoints.dbAdapter}/sessions');
    return (response.data as List).map((e) => Session.fromJson(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virtual S3 Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _filesFuture = _fetchFiles();
              _tagsFuture = _fetchTags();
              _sessionsFuture = _fetchSessions();
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: FutureBuilder<List<VirtualFile>>(
              future: _filesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                
                final files = snapshot.data!;
                if (files.isEmpty) {
                  return const Center(child: Text('No files found for current filters.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: files.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                      title: Text(file.path, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bucket: ${file.bucket}'),
                          Text('Created: ${file.createdAt.toLocal().toString().split('.')[0]}'),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            children: file.tags.map((t) => Chip(
                              label: Text(t, style: const TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            )).toList(),
                          ),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(file.status),
                        backgroundColor: Colors.green.shade50,
                        labelStyle: const TextStyle(color: Colors.green, fontSize: 10),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<List<Tag>>(
              future: _tagsFuture,
              builder: (context, snapshot) {
                return DropdownButtonFormField<Tag>(
                  decoration: const InputDecoration(labelText: 'Filter by Tag', border: OutlineInputBorder(), isDense: true),
                  initialValue: _selectedTag,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Tags')),
                    ...?snapshot.data?.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedTag = val;
                      _filesFuture = _fetchFiles();
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FutureBuilder<List<Session>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                return DropdownButtonFormField<Session>(
                  decoration: const InputDecoration(labelText: 'Filter by Session', border: OutlineInputBorder(), isDense: true),
                  initialValue: _selectedSession,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Sessions')),
                    ...?snapshot.data?.map((s) => DropdownMenuItem(value: s, child: Text(s.id.substring(0, 8)))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedSession = val;
                      _filesFuture = _fetchFiles();
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
