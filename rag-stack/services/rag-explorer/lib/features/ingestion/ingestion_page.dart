import 'dart:io';
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
  final Set<Tag> _selectedTags = {};
  bool _forceReingest = false;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;
  List<String> _allowedExtensions = [];
  final List<String> _uploadingFiles = [];
  final Set<String> _selectedObjects = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final service = ref.read(ingestionServiceProvider.notifier);
    
    // Fetch tags, buckets, and extensions in parallel
    final results = await Future.wait([
      service.getTags(),
      service.getBuckets(),
      service.getAllowedExtensions(),
    ]);
    
    final tags = results[0] as List<Tag>;
    final buckets = results[1] as List<String>;
    final extensions = results[2] as List<String>;
    final config = ref.read(appConfigProvider);
    
    if (mounted) {
      setState(() {
        _tags = tags;
        _allowedExtensions = extensions;
        if (tags.isNotEmpty && _selectedTags.isEmpty) {
          _selectedTags.add(tags.first);
        }
        
        // Resolve bucket
        if (buckets.isNotEmpty) {
          if (buckets.contains(config.defaultBucketName)) {
            _selectedBucket = config.defaultBucketName;
          } else {
            // Try to find a bucket with 'rag-codebase' in the name
            try {
              _selectedBucket = buckets.firstWhere(
                (b) => b.contains('rag-codebase'),
              );
            } catch (_) {
              _selectedBucket = buckets.first;
            }
          }
        }
        
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
      type: _allowedExtensions.isNotEmpty ? FileType.custom : FileType.any,
      allowedExtensions: _allowedExtensions.isNotEmpty 
        ? _allowedExtensions.map((e) => e.replaceAll('.', '')).toList() 
        : null,
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
        
        setState(() {
          _uploadingFiles.add(file.name);
          _statusMessage = 'Uploading ${file.name}...';
        });
        
        // Use prefix if specified, ensuring it ends with /
        String key = file.name;
        if (_prefix.isNotEmpty) {
          final cleanPrefix = _prefix.endsWith('/') ? _prefix : '$_prefix/';
          key = '$cleanPrefix$key';
        }
        
        final success = await service.uploadFile(_selectedBucket!, key, file.bytes!);
        if (success) successCount++;

        setState(() {
          _uploadingFiles.remove(file.name);
        });
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadingFiles.clear();
          _statusMessage = 'Successfully uploaded $successCount of ${result.files.length} files.';
        });
        _loadObjects();
      }
    }
  }

  Future<void> _pickAndUploadFolder() async {
    if (_selectedBucket == null) return;
    
    final String? directoryPath = await FilePicker.getDirectoryPath();

    if (directoryPath != null) {
      final dir = Directory(directoryPath);
      if (!dir.existsSync()) return;

      setState(() {
        _isLoading = true;
        _statusMessage = 'Scanning folder...';
        _isError = false;
      });

      try {
        final List<FileSystemEntity> entities = dir.listSync(recursive: true);
        final List<File> files = entities.whereType<File>().where((file) {
          if (_allowedExtensions.isEmpty) return true;
          final fileName = file.path.toLowerCase();
          return _allowedExtensions.any((ext) => fileName.endsWith(ext.toLowerCase()));
        }).toList();
        
        if (files.isEmpty) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'No files found in selected folder.';
          });
          return;
        }

        setState(() {
          _statusMessage = 'Uploading ${files.length} files...';
        });

        final service = ref.read(ingestionServiceProvider.notifier);
        int successCount = 0;
        
        // We want to preserve the folder structure starting from the selected folder
        final parentPath = dir.parent.path;

        for (final file in files) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          setState(() {
            _uploadingFiles.add(fileName);
            _statusMessage = 'Uploading $fileName...';
          });

          String relativePath = file.path.substring(parentPath.length);
          if (relativePath.startsWith(Platform.pathSeparator)) {
            relativePath = relativePath.substring(1);
          }
          
          // Ensure forward slashes for S3
          String key = relativePath.replaceAll(Platform.pathSeparator, '/');
          
          if (_prefix.isNotEmpty) {
             key = _prefix.endsWith('/') ? '$_prefix$key' : '$_prefix/$key';
          }

          final bytes = await file.readAsBytes();
          final success = await service.uploadFile(_selectedBucket!, key, bytes);
          if (success) successCount++;

          setState(() {
            _uploadingFiles.remove(fileName);
          });
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
            _uploadingFiles.clear();
            _statusMessage = 'Successfully uploaded $successCount of ${files.length} files.';
          });
          _loadObjects();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isError = true;
            _statusMessage = 'Error scanning folder: $e';
          });
        }
      }
    }
  }

  Future<void> _displayObject(Map<String, dynamic> obj) async {
    final key = obj['Key'] as String;
    if (_selectedBucket == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching content...';
    });

    final service = ref.read(ingestionServiceProvider.notifier);
    final content = await service.getObjectContent(_selectedBucket!, key);

    if (mounted) {
      setState(() => _isLoading = false);
      
      if (content == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch object content.'))
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(key.split('/').last),
          content: SizedBox(
            width: 800,
            height: 600,
            child: SingleChildScrollView(
              child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    }
  }

  Future<void> _deleteObject(Map<String, dynamic> obj) async {
    final key = obj['Key'] as String;
    if (_selectedBucket == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Object?'),
        content: Text('Are you sure you want to delete "$key" from S3?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Deleting $key...';
      });

      final service = ref.read(ingestionServiceProvider.notifier);
      final success = await service.deleteObject(_selectedBucket!, key);

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (success) {
            _statusMessage = 'Object deleted successfully.';
          } else {
            _isError = true;
            _statusMessage = 'Failed to delete object.';
          }
        });
        _loadObjects();
      }
    }
  }

  Future<void> _deleteSelectedObjects() async {
    if (_selectedBucket == null || _selectedObjects.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Objects?'),
        content: Text('Are you sure you want to delete ${_selectedObjects.length} objects from S3?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final toDelete = List<String>.from(_selectedObjects);
      setState(() {
        _isLoading = true;
        _statusMessage = 'Deleting ${toDelete.length} objects...';
        _selectedObjects.clear();
      });

      final service = ref.read(ingestionServiceProvider.notifier);
      int successCount = 0;
      for (final key in toDelete) {
        final success = await service.deleteObject(_selectedBucket!, key);
        if (success) successCount++;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Successfully deleted $successCount of ${toDelete.length} objects.';
        });
        _loadObjects();
      }
    }
  }

  Future<void> _triggerIngestion() async {
    if (_selectedBucket == null || _selectedTags.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Triggering ingestion...';
      _isError = false;
    });

    try {
      final service = ref.read(ingestionServiceProvider.notifier);
      final result = await service.triggerIngest(
        bucketName: _selectedBucket!,
        tagIds: _selectedTags.map((t) => t.id).toList(),
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _statusMessage = 'Exception: $e';
        });
      }
    }
  }

  void _showCreateTagDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tag Name', hintText: 'e.g., technical-docs'),
          autofocus: true,
          onSubmitted: (_) {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              _createTag(name, context);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _createTag(name, context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTag(String name, BuildContext dialogContext) async {
    final service = ref.read(ingestionServiceProvider.notifier);
    
    // Create tag synchronously
    final newTag = await service.createTag(name);
    
    if (mounted) {
      if (newTag != null) {
        setState(() {
          _tags.add(newTag);
          _selectedTags.add(newTag);
        });
      }
      // Close dialog as soon as creation attempt is done
      Navigator.pop(dialogContext);
    }
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
                    Text('Knowledge Tags', style: TextStyle(fontWeight: FontWeight.bold)),
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
            if (_tags.isEmpty)
              const Text('No tags available. Create one to get started.', style: TextStyle(color: Colors.grey, fontSize: 13))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((tag) {
                  final isSelected = _selectedTags.contains(tag);
                  return FilterChip(
                    label: Text(tag.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(tag);
                        } else {
                          // Don't allow deselecting if it's the only one? 
                          // Actually, multiple tags are allowed, let's allow empty if they want, 
                          // but start ingestion check will block it.
                          _selectedTags.remove(tag);
                        }
                      });
                    },
                    selectedColor: Colors.blue.withValues(alpha: 0.2),
                    checkmarkColor: Colors.blue,
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            const Text(
              'Tags partition the vector store and allow context isolation. Select multiple to index into all of them.',
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
    final canIngest = _selectedBucket != null && _selectedTags.isNotEmpty && !_isLoading;
    return Center(
      child: Column(
        children: [
          SizedBox(
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
          if (_isLoading && _uploadingFiles.isNotEmpty) ...[
             const SizedBox(height: 16),
             _buildUploadingFilesWindow(darkMode),
          ]
        ],
      ),
    );
  }

  Widget _buildUploadingFilesWindow(bool darkMode) {
    return Container(
      height: 120,
      width: 400,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: darkMode ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: darkMode ? Colors.grey[800]! : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Uploading Files...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text('${_uploadingFiles.length} remaining', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _uploadingFiles.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _uploadingFiles[index],
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(bool darkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isError 
            ? (darkMode ? Colors.red[900]!.withValues(alpha: 0.3) : Colors.red[50]) 
            : (darkMode ? Colors.green[900]!.withValues(alpha: 0.3) : Colors.green[50]),
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
    final allSelected = _objects.isNotEmpty && _selectedObjects.length == _objects.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedObjects.addAll(_objects.map((o) => o['Key'] as String));
                      } else {
                        _selectedObjects.clear();
                      }
                    });
                  },
                ),
                Text('Objects in $_selectedBucket', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                if (_selectedObjects.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteSelectedObjects,
                    icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 18),
                    label: Text('Delete Selected (${_selectedObjects.length})', style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(width: 8),
                Text('${_objects.length} files found', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
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
                    final isSelected = _selectedObjects.contains(obj['Key']);
                    return ListTile(
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedObjects.add(obj['Key'] as String);
                            } else {
                              _selectedObjects.remove(obj['Key'] as String);
                            }
                          });
                        },
                      ),
                      title: Text(obj['Key'] ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${(obj['Size'] ?? 0) / 1024} KB • Last Modified: ${obj['LastModified']}', style: const TextStyle(fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (val) {
                          if (val == 'display') _displayObject(obj);
                          if (val == 'delete') _deleteObject(obj);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'display', child: Text('Display Content')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete Object', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                      dense: true,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
