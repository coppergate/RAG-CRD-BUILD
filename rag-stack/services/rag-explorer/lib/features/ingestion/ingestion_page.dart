import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/tag.dart';
import '../../core/services/ingestion_service.dart';
import '../../app_config_provider.dart';

class IngestionPage extends ConsumerStatefulWidget {
  const IngestionPage({super.key});

  @override
  ConsumerState<IngestionPage> createState() => _IngestionPageState();
}

class _IngestionPageState extends ConsumerState<IngestionPage> {
  String? _selectedBucket;
  List<Map<String, dynamic>> _objects = [];
  String _prefix = '';
  List<Tag> _tags = [];
  Tag? _selectedTag;
  bool _forceReingest = false;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final service = ref.read(ingestionServiceProvider.notifier);
    final tags = await service.getTags();
    final config = ref.read(appConfigProvider);
    
    if (mounted) {
      setState(() {
        _tags = tags;
        _selectedBucket = config.defaultBucketName.isNotEmpty ? config.defaultBucketName : null;
        if (tags.isNotEmpty) _selectedTag = tags.first;
        _isLoading = false;
      });
      if (_selectedBucket != null) {
        _loadObjects();
      }
    }
  }

  Future<void> _loadObjects() async {
    if (_selectedBucket == null) return;
    final service = ref.read(ingestionServiceProvider.notifier);
    final objects = await service.getObjects(_selectedBucket!, prefix: _prefix);
    if (mounted) {
      setState(() {
        _objects = objects;
      });
    }
  }

  Future<void> _pickAndUploadFiles() async {
    if (_selectedBucket == null) return;
    
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Uploading ${result.files.length} files...';
        _isError = false;
      });

      final service = ref.read(ingestionServiceProvider.notifier);
      int successCount = 0;
      
      for (final file in result.files) {
        if (file.bytes == null) continue;
        
        // Use prefix if specified, ensuring it ends with /
        String key = file.name;
        if (_prefix.isNotEmpty) {
          final cleanPrefix = _prefix.endsWith('/') ? _prefix : '$_prefix/';
          key = '$cleanPrefix$key';
        }
        
        final success = await service.uploadFile(_selectedBucket!, key, file.bytes!);
        if (success) successCount++;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Successfully uploaded $successCount of ${result.files.length} files.';
        });
        _loadObjects();
      }
    }
  }

  Future<void> _pickAndUploadFolder() async {
    if (_selectedBucket == null) return;
    
    // getDirectoryPath is not supported on Web, but this is desktop/mobile
    final String? directoryPath = await FilePicker.getDirectoryPath();

    if (directoryPath != null) {
      // In a real desktop app, we'd recursively read the directory.
      // But file_picker's getDirectoryPath only returns the path string.
      // For cross-platform/web-safety, we usually use pickFiles with web: true
      // or similar, but since we are desktop-focused, we might need 'dart:io'.
      // However, the prompt says we should replicate rag-web-ui functionality.
      // rag-web-ui uses HTML <input webkitdirectory>.
      
      setState(() {
        _isError = true;
        _statusMessage = 'Folder upload is currently only supported via individual file selection in this version.';
      });
    }
  }

  Future<void> _triggerIngestion() async {
    if (_selectedBucket == null || _selectedTag == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Triggering ingestion...';
      _isError = false;
    });

    final service = ref.read(ingestionServiceProvider.notifier);
    final result = await service.triggerIngest(
      bucketName: _selectedBucket!,
      tagId: _selectedTag!.id,
      prefix: _prefix,
      forceReingest: _forceReingest,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.containsKey('error')) {
          _isError = true;
          _statusMessage = 'Error: ${result['error']}';
        } else {
          _statusMessage = 'Ingestion triggered successfully! Check system logs for progress.';
        }
      });
    }
  }

  void _showCreateTagDialog() {
    final controller = TextEditingController();
    bool isCreating = false;

    void handleCreate(BuildContext dialogContext) {
      if (isCreating) return;
      final name = controller.text.trim();
      if (name.isNotEmpty) {
        isCreating = true;
        Navigator.pop(dialogContext);

        final service = ref.read(ingestionServiceProvider.notifier);
        service.createTag(name).then((newTag) {
          if (newTag != null && mounted) {
            setState(() {
              _tags.add(newTag);
              _selectedTag = newTag;
            });
          }
        });
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New Tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tag Name', hintText: 'e.g., technical-docs'),
          autofocus: true,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => handleCreate(dialogContext),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => handleCreate(dialogContext),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = ref.watch(appConfigProvider).darkMode;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Ingestion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader('Manage Knowledge Sources'),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildBucketSelector(darkMode)),
                          const SizedBox(width: 24),
                          Expanded(flex: 2, child: _buildTagSelector(darkMode)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildOptions(darkMode),
                      const SizedBox(height: 24),
                      _buildUploadArea(darkMode),
                      const SizedBox(height: 32),
                      _buildActionArea(darkMode),
                      const SizedBox(height: 32),
                      if (_statusMessage != null) _buildStatusBanner(darkMode),
                      const SizedBox(height: 32),
                      _buildObjectList(darkMode),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('Use the configured bucket and select a tag. Optionally set a prefix for sub-indexing.', 
            style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildBucketSelector(bool darkMode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.storage, size: 18),
                SizedBox(width: 8),
                Text('S3 Bucket', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _selectedBucket ?? '',
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'S3 Bucket (from configuration)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Prefix / Sub-index (Optional)',
                hintText: 'e.g., docs/2024/',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_open),
              ),
              onChanged: (val) {
                _prefix = val;
              },
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadObjects(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSelector(bool darkMode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.label, size: 18),
                    SizedBox(width: 8),
                    Text('Knowledge Tag', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                  onPressed: _showCreateTagDialog,
                  tooltip: 'Create New Tag',
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Tag>(
              value: _selectedTag,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: _tags.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
              onChanged: (val) => setState(() => _selectedTag = val),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tags partition the vector store and allow context isolation.',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(bool darkMode) {
    return Card(
      child: SwitchListTile(
        title: const Text('Force Re-ingest'),
        subtitle: const Text('Re-process and re-embed all files even if they already exist in the vector store.'),
        value: _forceReingest,
        onChanged: (val) => setState(() => _forceReingest = val),
        secondary: Icon(Icons.refresh, color: _forceReingest ? Colors.orange : Colors.grey),
      ),
    );
  }

  Widget _buildUploadArea(bool darkMode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_upload, size: 18),
                SizedBox(width: 8),
                Text('S3 Upload', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedBucket != null ? _pickAndUploadFiles : null,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload Files'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedBucket != null ? _pickAndUploadFolder : null,
                    icon: const Icon(Icons.drive_folder_upload),
                    label: const Text('Upload Folder'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Files will be uploaded to bucket: ${_selectedBucket ?? "none"}${_prefix.isNotEmpty ? " into prefix: $_prefix" : ""}',
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea(bool darkMode) {
    final canIngest = _selectedBucket != null && _selectedTag != null && !_isLoading;
    return Center(
      child: SizedBox(
        width: 300,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: canIngest ? _triggerIngestion : null,
          icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.rocket_launch),
          label: Text(_isLoading ? 'Processing...' : 'Start Ingestion'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(bool darkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isError 
            ? (darkMode ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50]) 
            : (darkMode ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50]),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isError ? Colors.red : Colors.green),
      ),
      child: Row(
        children: [
          Icon(_isError ? Icons.error : Icons.check_circle, color: _isError ? Colors.red : Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_statusMessage!, style: TextStyle(color: _isError ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _statusMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectList(bool darkMode) {
    if (_selectedBucket == null) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Objects in ${_selectedBucket}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${_objects.length} files found', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 300,
          decoration: BoxDecoration(
            border: Border.all(color: darkMode ? Colors.grey[800]! : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _objects.isEmpty
              ? const Center(child: Text('No objects found matching the prefix.'))
              : ListView.separated(
                  itemCount: _objects.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final obj = _objects[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
                      title: Text(obj['Key'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${(obj['Size'] ?? 0) / 1024} KB • Last Modified: ${obj['LastModified']}', style: const TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right, size: 16),
                      dense: true,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
