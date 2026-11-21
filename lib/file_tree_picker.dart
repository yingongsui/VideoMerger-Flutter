import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_service.dart';

class _StorageVolume {
  final String name;
  final String path;
  final IconData icon;

  const _StorageVolume({
    required this.name,
    required this.path,
    required this.icon,
  });
}

/// Multi-volume file/folder browser with persistent path memory and cached video thumbnails.
class MultiFileTreePicker extends StatefulWidget {
  final List<String> allowedExtensions;
  final bool pickFolderMode;

  const MultiFileTreePicker({
    super.key,
    this.allowedExtensions = const [],
    this.pickFolderMode = false,
  });

  @override
  State<MultiFileTreePicker> createState() => _MultiFileTreePickerState();
}

class _MultiFileTreePickerState extends State<MultiFileTreePicker> {
  static const String _prefLastPathKey = 'last_accessed_path';
  static const String _internalRoot = '/storage/emulated/0';

  Directory? _currentDir;
  final List<_StorageVolume> _storageVolumes = [];
  List<FileSystemEntity> _entities = [];
  final Set<String> _selectedPaths = {};
  final Map<String, Future<String?>> _thumbnailFutures = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _detectStorageVolumesAndRestore();
  }

  Future<void> _saveLastPath(String? path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (path == null) {
        await prefs.remove(_prefLastPathKey);
      } else {
        await prefs.setString(_prefLastPathKey, path);
      }
    } catch (_) {}
  }

  Future<void> _detectStorageVolumesAndRestore() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    _storageVolumes.clear();

    _storageVolumes.add(
      const _StorageVolume(
        name: 'Internal Shared Storage',
        path: _internalRoot,
        icon: Icons.phone_android_rounded,
      ),
    );

    try {
      final List<Directory>? extDirs = await getExternalStorageDirectories();
      if (extDirs != null) {
        for (final dir in extDirs) {
          final fullPath = dir.path;
          if (!fullPath.contains('emulated') && fullPath.contains('/storage/')) {
            final pathParts = fullPath.split('/');
            final storageIdx = pathParts.indexOf('storage');
            if (storageIdx != -1 && storageIdx + 1 < pathParts.length) {
              final volumeId = pathParts[storageIdx + 1];
              final sdRootPath = '/storage/$volumeId';
              if (!_storageVolumes.any((v) => v.path == sdRootPath)) {
                _storageVolumes.add(
                  _StorageVolume(
                    name: 'External SD Card ($volumeId)',
                    path: sdRootPath,
                    icon: Icons.sd_card_rounded,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[FileTreePicker] External volume scan skipped: $e');
    }

    String? savedPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedPath = prefs.getString(_prefLastPathKey);
    } catch (_) {}

    if (savedPath != null) {
      final savedDir = Directory(savedPath);
      if (await savedDir.exists()) {
        await _openDirectory(savedDir);
        return;
      }
    }

    if (_storageVolumes.length == 1) {
      await _openDirectory(Directory(_storageVolumes.first.path));
    } else if (mounted) {
      setState(() {
        _currentDir = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _openDirectory(Directory dir) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _currentDir = dir;
    });
    _saveLastPath(dir.path);

    final List<FileSystemEntity> filtered = [];
    try {
      final list = await dir.list(followLinks: false).toList();
      list.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      for (final entity in list) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.') ||
            name == 'ANDROID_SECURE' ||
            name == 'LOST.DIR' ||
            name == 'Android') {
          continue;
        }
        if (entity is Directory) {
          filtered.add(entity);
        } else if (!widget.pickFolderMode && entity is File) {
          final lower = entity.path.toLowerCase();
          if (widget.allowedExtensions.any((ext) => lower.endsWith(ext))) {
            filtered.add(entity);
          }
        }
      }
    } catch (err) {
      debugPrint('[FileTreePicker] Directory read error (${dir.path}): $err');
    }

    if (!mounted) return;
    setState(() {
      _entities = filtered;
      _isLoading = false;
    });
  }

  Future<String?> _getThumbnailFuture(String path) {
    return _thumbnailFutures.putIfAbsent(
      path,
      () => VideoService.generateThumbnail(path),
    );
  }

  bool get _isAtVolumeRoot => _currentDir == null;
  bool get _isOnlyInternalStorage => _storageVolumes.length == 1;

  bool get _isAtTopMount =>
      _currentDir != null &&
      _storageVolumes.any((v) => v.path == _currentDir!.path);

  bool _handleNavigateUp() {
    if (_isAtVolumeRoot) {
      return true; // Allow popping route
    }
    if (_isAtTopMount) {
      if (_isOnlyInternalStorage) {
        return true; // Allow popping route
      }
      _saveLastPath(null);
      setState(() {
        _currentDir = null;
        _entities = [];
      });
      return false;
    }
    _openDirectory(_currentDir!.parent);
    return false;
  }

  String _resolveTitle() {
    if (_isAtVolumeRoot) {
      return widget.pickFolderMode ? 'Select Save Volume' : 'Select Storage';
    }
    final path = _currentDir!.path;
    if (path == _internalRoot) return 'Internal Storage';
    for (final vol in _storageVolumes) {
      if (vol.path == path) return vol.name;
    }
    return path.split('/').last;
  }

  List<File> get _selectableFilesInCurrentDir =>
      _entities.whereType<File>().toList();

  void _toggleSelectAll() {
    final files = _selectableFilesInCurrentDir;
    if (files.isEmpty) return;
    final allSelected = files.every((f) => _selectedPaths.contains(f.path));
    setState(() {
      if (allSelected) {
        for (final f in files) {
          _selectedPaths.remove(f.path);
        }
      } else {
        for (final f in files) {
          _selectedPaths.add(f.path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filesInDir = _selectableFilesInCurrentDir;
    final allSelected =
        filesInDir.isNotEmpty &&
        filesInDir.every((f) => _selectedPaths.contains(f.path));

    return PopScope(
      canPop: _isAtVolumeRoot || (_isAtTopMount && _isOnlyInternalStorage),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleNavigateUp();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_resolveTitle()),
          leading: IconButton(
            icon: Icon(
              (_isAtVolumeRoot || (_isAtTopMount && _isOnlyInternalStorage))
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
            onPressed: () {
              if (_handleNavigateUp()) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (!widget.pickFolderMode &&
                !_isAtVolumeRoot &&
                filesInDir.isNotEmpty)
              IconButton(
                tooltip: allSelected ? 'Deselect all in folder' : 'Select all in folder',
                icon: Icon(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                ),
                onPressed: _toggleSelectAll,
              ),
            if (widget.pickFolderMode && !_isAtVolumeRoot)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Use Here'),
                  onPressed: () => Navigator.pop(context, [_currentDir!.path]),
                ),
              )
            else if (!widget.pickFolderMode && _selectedPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Add (${_selectedPaths.length})'),
                  onPressed: () =>
                      Navigator.pop(context, _selectedPaths.toList()),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (!_isAtVolumeRoot)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentDir!.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!_isOnlyInternalStorage)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          _saveLastPath(null);
                          setState(() {
                            _currentDir = null;
                            _entities = [];
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Volumes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _isAtVolumeRoot
                      ? _buildVolumeList(colorScheme)
                      : _entities.isEmpty
                          ? _buildEmptyDirectoryState(colorScheme)
                          : _buildEntityList(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeList(ColorScheme colorScheme) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _storageVolumes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final vol = _storageVolumes[idx];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(vol.icon, color: colorScheme.onPrimaryContainer),
            ),
            title: Text(
              vol.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            subtitle: Text(
              vol.path,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openDirectory(Directory(vol.path)),
          ),
        );
      },
    );
  }

  Widget _buildEmptyDirectoryState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.pickFolderMode
                  ? Icons.folder_off_outlined
                  : Icons.video_file_outlined,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              widget.pickFolderMode
                  ? 'No accessible subfolders here.'
                  : 'No supported video files in this folder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityList(ColorScheme colorScheme) {
    return ListView.builder(
      itemCount: _entities.length,
      itemBuilder: (context, index) {
        final entity = _entities[index];
        final isDir = entity is Directory;
        final name = entity.path.split('/').last;
        final isSelected = _selectedPaths.contains(entity.path);

        return ListTile(
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(
            alpha: 0.28,
          ),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isDir
                  ? Container(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.55,
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        color: colorScheme.primary,
                        size: 26,
                      ),
                    )
                  : FutureBuilder<String?>(
                      future: _getThumbnailFuture(entity.path),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.data != null) {
                          return Image.file(
                            File(snapshot.data!),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildVideoPlaceholder(colorScheme),
                          );
                        }
                        return _buildVideoPlaceholder(colorScheme);
                      },
                    ),
            ),
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          trailing: isDir
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                )
              : Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPaths.add(entity.path);
                      } else {
                        _selectedPaths.remove(entity.path);
                      }
                    });
                  },
                ),
          onTap: () {
            if (isDir) {
              _openDirectory(entity);
            } else {
              setState(() {
                if (isSelected) {
                  _selectedPaths.remove(entity.path);
                } else {
                  _selectedPaths.add(entity.path);
                }
              });
            }
          },
        );
      },
    );
  }

  Widget _buildVideoPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        color: colorScheme.primary,
        size: 22,
      ),
    );
  }
}
