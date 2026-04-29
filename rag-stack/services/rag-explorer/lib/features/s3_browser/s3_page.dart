import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/models/metrics.dart';
import '../../core/models/tag.dart';
import '../../core/models/session.dart';
import '../../app_config_provider.dart';

class S3Page extends ConsumerStatefulWidget {
  const S3Page({super.key});

  @override
  ConsumerState<S3Page> createState() => _S3PageState();
}

class _S3PageState extends ConsumerState<S3Page> {
  late Future<List<VirtualFile>> _filesFuture;
  Tag? _selectedTag;
  Session? _selectedSession;
  late Future<List<Tag>> _tagsFuture;
  late Future<List<Session>> _sessionsFuture;
  final Set<String> _selectedFiles = {};
  int? _lastSelectedIndex;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _filesFuture = _fetchFiles();
      _tagsFuture = _fetchTags();
      _sessionsFuture = _fetchSessions();
      _selectedFiles.clear();
    });
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete ${_selectedFiles.length} objects from S3?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final config = ref.read(appConfigProvider);
      final client = ApiClient(config);
      
      final files = await _filesFuture;
      for (final path in _selectedFiles) {
        final file = files.firstWhere((f) => f.path == path);
        await client.delete('${config.ragAdminApiUrl}/api/s3/buckets/${file.bucket}/${file.path}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully deleted ${_selectedFiles.length} objects')),
      );
      _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting objects: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _viewFileContent(VirtualFile file) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.path, style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<String>(
            future: _fetchFileContent(file),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              return SingleChildScrollView(
                child: SelectableText(
                  snapshot.data ?? 'No content',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<String> _fetchFileContent(VirtualFile file) async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    final response = await client.get('${config.ragAdminApiUrl}/api/s3/buckets/${file.bucket}/${file.path}');
    if (response.data is String) return response.data;
    return response.data.toString();
  }

  Future<List<VirtualFile>> _fetchFiles() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    Map<String, dynamic> queryParams = {};
    if (_selectedTag != null) queryParams['tag_id'] = _selectedTag!.id;
    if (_selectedSession != null) queryParams['session_id'] = _selectedSession!.id;
    
    final response = await client.get('${config.ragAdminApiUrl}/api/db/storage/files', queryParameters: queryParams);
    return (response.data as List).map((e) => VirtualFile.fromJson(e)).toList();
  }

  Future<List<Tag>> _fetchTags() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    final response = await client.get('${config.ragAdminApiUrl}/api/db/tags');
    return (response.data as List).map((e) => Tag.fromJson(e)).toList();
  }

  Future<List<Session>> _fetchSessions() async {
    final config = ref.read(appConfigProvider);
    final client = ApiClient(config);
    final response = await client.get('${config.ragAdminApiUrl}/api/db/sessions');
    return (response.data as List).map((e) => Session.fromJson(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virtual S3 Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
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
                    final isSelected = _selectedFiles.contains(file.path);
                    
                    return InkWell(
                      onDoubleTap: () => _viewFileContent(file),
                      child: ListTile(
                        selected: isSelected,
                        onTap: () {
                          final keys = HardwareKeyboard.instance.logicalKeysPressed;
                          final isShift = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
                          final isControl = keys.contains(LogicalKeyboardKey.controlLeft) || keys.contains(LogicalKeyboardKey.controlRight) ||
                                            keys.contains(LogicalKeyboardKey.metaLeft) || keys.contains(LogicalKeyboardKey.metaRight);

                          setState(() {
                            if (isShift && _lastSelectedIndex != null) {
                              final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
                              final end = _lastSelectedIndex! < index ? index : _lastSelectedIndex!;
                              for (int i = start; i <= end; i++) {
                                _selectedFiles.add(files[i].path);
                              }
                            } else if (isControl) {
                              if (_selectedFiles.contains(file.path)) {
                                _selectedFiles.remove(file.path);
                              } else {
                                _selectedFiles.add(file.path);
                              }
                              _lastSelectedIndex = index;
                            } else {
                              _selectedFiles.clear();
                              _selectedFiles.add(file.path);
                              _lastSelectedIndex = index;
                            }
                          });
                        },
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedFiles.add(file.path);
                                  } else {
                                    _selectedFiles.remove(file.path);
                                  }
                                  _lastSelectedIndex = index;
                                });
                              },
                            ),
                            const Icon(Icons.insert_drive_file, color: Colors.blue),
                          ],
                        ),
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
                                label: Text(t, style: TextStyle(fontSize: 10, color: isDark ? Colors.blue.shade200 : Colors.blue.shade900)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                backgroundColor: isDark ? Colors.blue.shade900.withOpacity(0.3) : Colors.blue.shade50,
                                side: BorderSide.none,
                              )).toList(),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'view') _viewFileContent(file);
                            if (val == 'delete') {
                              setState(() => _selectedFiles.add(file.path));
                              _deleteSelectedFiles();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'view', child: Text('View Content')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                          child: Chip(
                            label: Text(file.status),
                            backgroundColor: isDark ? Colors.green.shade900.withOpacity(0.3) : Colors.green.shade50,
                            labelStyle: TextStyle(color: isDark ? Colors.green.shade300 : Colors.green, fontSize: 10),
                            side: BorderSide.none,
                          ),
                        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FutureBuilder<List<Tag>>(
                  future: _tagsFuture,
                  builder: (context, snapshot) {
                    return DropdownButtonFormField<Tag>(
                      decoration: const InputDecoration(labelText: 'Filter by Tag', border: OutlineInputBorder(), isDense: true),
                      value: _selectedTag,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Tags')),
                        ...?snapshot.data?.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedTag = val;
                          _filesFuture = _fetchFiles();
                          _selectedFiles.clear();
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
                      value: _selectedSession,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Sessions')),
                        ...?snapshot.data?.map((s) => DropdownMenuItem(value: s, child: Text(s.id.substring(0, 8)))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedSession = val;
                          _filesFuture = _fetchFiles();
                          _selectedFiles.clear();
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          if (_selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${_selectedFiles.length} items selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedFiles.clear()),
                  child: const Text('Clear Selection'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isDeleting ? null : _deleteSelectedFiles,
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  label: const Text('Delete Selected', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
