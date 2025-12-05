import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class LocalStorageService {
  static Directory? _appDir;
  
  /// Gets the application documents directory
  static Future<Directory> get appDir async {
    if (_appDir != null) return _appDir!;
    
    final directory = await getApplicationDocumentsDirectory();
    _appDir = Directory(path.join(directory.path, 'EstudiaFacil'));
    
    // Create directory if it doesn't exist
    if (!await _appDir!.exists()) {
      await _appDir!.create(recursive: true);
    }
    
    return _appDir!;
  }
  
  /// Gets the user's storage directory
  static Future<Directory> getUserDir(String userId) async {
    final appDir = await LocalStorageService.appDir;
    final userDir = Directory(path.join(appDir.path, 'user_$userId'));
    
    if (!await userDir.exists()) {
      await userDir.create(recursive: true);
    }
    
    return userDir;
  }
  
  /// Gets the documents directory for a user
  static Future<Directory> getDocumentsDir(String userId) async {
    final userDir = await getUserDir(userId);
    final docsDir = Directory(path.join(userDir.path, 'documents'));
    
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    
    return docsDir;
  }
  
  /// Gets the directories directory for a user
  static Future<Directory> getDirectoriesDir(String userId) async {
    final userDir = await getUserDir(userId);
    final dirsDir = Directory(path.join(userDir.path, 'directories'));
    
    if (!await dirsDir.exists()) {
      await dirsDir.create(recursive: true);
    }
    
    return dirsDir;
  }
  
  /// Saves a PDF file locally
  static Future<String> savePdfFile(String userId, String fileName, Uint8List fileData) async {
    final docsDir = await getDocumentsDir(userId);
    final file = File(path.join(docsDir.path, fileName));
    
    await file.writeAsBytes(fileData);
    return file.path;
  }
  
  /// Saves a summary file locally, optionally inside a relative subfolder
  static Future<String> saveSummaryFile(
      String userId, String fileName, String content,
      [String? relativePath]) async {
    final docsDir = await getDocumentsDir(userId);
    final targetDir = (relativePath != null && relativePath.isNotEmpty)
        ? Directory(path.join(docsDir.path, relativePath))
        : docsDir;

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final file = File(path.join(targetDir.path, fileName));
    await file.writeAsString(content);
    return file.path;
  }
  
  /// Creates a directory locally
  static Future<String> createDirectory(String userId, String dirName, String? parentPath, {String? colorHex}) async {
    final dirsDir = await getDirectoriesDir(userId);
    final fullPath = parentPath != null && parentPath.isNotEmpty 
        ? path.join(dirsDir.path, parentPath, dirName)
        : path.join(dirsDir.path, dirName);
    
    final directory = Directory(fullPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    // Save metadata if color is provided
    if (colorHex != null) {
      await writeDirMeta(directory, {'color': colorHex});
    }
    
    return fullPath;
  }
  
  /// Lists files in a directory
  static Future<List<FileSystemEntity>> listFiles(String userId, String? relativePath) async {
    final docsDir = await getDocumentsDir(userId);
    final targetDir = relativePath != null && relativePath.isNotEmpty
        ? Directory(path.join(docsDir.path, relativePath))
        : docsDir;
    
    if (!await targetDir.exists()) {
      return [];
    }
    
    return targetDir.listSync();
  }
  
  /// Lists directories
  static Future<List<Directory>> listDirectories(String userId, String? relativePath) async {
    final dirsDir = await getDirectoriesDir(userId);
    final targetDir = relativePath != null && relativePath.isNotEmpty
        ? Directory(path.join(dirsDir.path, relativePath))
        : dirsDir;
    
    if (!await targetDir.exists()) {
      return [];
    }
    
    return targetDir.listSync()
        .whereType<Directory>()
        .toList();
  }
  
  /// Deletes a file
  static Future<bool> deleteFile(String userId, String fileName, String? relativePath) async {
    try {
      final docsDir = await getDocumentsDir(userId);
      final filePath = relativePath != null && relativePath.isNotEmpty
          ? path.join(docsDir.path, relativePath, fileName)
          : path.join(docsDir.path, fileName);
      
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// Deletes a directory
  static Future<bool> deleteDirectory(String userId, String dirName, String? relativePath) async {
    try {
      final dirsDir = await getDirectoriesDir(userId);
      final dirPath = relativePath != null && relativePath.isNotEmpty
          ? path.join(dirsDir.path, relativePath, dirName)
          : path.join(dirsDir.path, dirName);
      
      final directory = Directory(dirPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Deletes a folder tree completely (both directories and documents)
  /// Used after successfully sharing a folder to cloud
  static Future<bool> deleteFolderTree(String userId, String folderRelativePath) async {
    try {
      bool success = true;
      
      // Delete from directories folder
      final dirsDir = await getDirectoriesDir(userId);
      final dirPath = path.join(dirsDir.path, folderRelativePath);
      final directory = Directory(dirPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      
      // Delete from documents folder (PDFs, TXTs)
      final docsDir = await getDocumentsDir(userId);
      final docsPath = path.join(docsDir.path, folderRelativePath);
      final docsDirectory = Directory(docsPath);
      if (await docsDirectory.exists()) {
        await docsDirectory.delete(recursive: true);
      }
      
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Moves a directory locally
  /// Returns the new relative path if successful, throws exception if failed
  static Future<String> moveDirectory(String userId, String sourcePath, String? newParentPath) async {
    try {
      final dirsDir = await getDirectoriesDir(userId);
      
      // Build absolute paths
      final sourceAbsPath = path.join(dirsDir.path, sourcePath);
      final sourceDir = Directory(sourceAbsPath);
      
      // Check if source directory exists
      if (!await sourceDir.exists()) {
        throw Exception('Carpeta no encontrada');
      }
      
      // Get the directory name from source path
      final dirName = path.basename(sourcePath);
      
      // Build destination path
      final destParentAbsPath = newParentPath != null && newParentPath.isNotEmpty
          ? path.join(dirsDir.path, newParentPath)
          : dirsDir.path;
      
      // Create destination parent directory if it doesn't exist
      final destParentDir = Directory(destParentAbsPath);
      if (!await destParentDir.exists()) {
        await destParentDir.create(recursive: true);
      }
      
      // Build final destination path
      final destAbsPath = path.join(destParentAbsPath, dirName);
      final destDir = Directory(destAbsPath);
      
      // Check if destination already exists
      if (await destDir.exists()) {
        // Generate unique name if destination exists
        int counter = 1;
        String uniqueName = dirName;
        Directory? finalDestDir;
        while (true) {
          uniqueName = '$dirName ($counter)';
          final newDestAbsPath = path.join(destParentAbsPath, uniqueName);
          finalDestDir = Directory(newDestAbsPath);
          if (!await finalDestDir.exists()) {
            break;
          }
          counter++;
        }
        await sourceDir.rename(finalDestDir.path);
        
        // Return new relative path
        return newParentPath != null && newParentPath.isNotEmpty
            ? '$newParentPath/$uniqueName'
            : uniqueName;
      }
      
      // Move the directory
      await sourceDir.rename(destAbsPath);
      
      // Return new relative path
      return newParentPath != null && newParentPath.isNotEmpty
          ? '$newParentPath/$dirName'
          : dirName;
    } catch (e) {
      throw Exception('Error al mover carpeta: ${e.toString()}');
    }
  }
  
  /// Updates directory attributes (name/color) in local storage.
  static Future<Map<String, dynamic>> updateDirectoryProperties(
    String userId,
    String? relativePath, {
    String? newName,
    String? colorHex,
  }) async {
    final dirsDir = await getDirectoriesDir(userId);
    final normalizedPath = (relativePath ?? '').trim();
    final targetAbsPath = normalizedPath.isNotEmpty
        ? path.join(dirsDir.path, normalizedPath)
        : dirsDir.path;
    Directory directory = Directory(targetAbsPath);

    if (!await directory.exists()) {
      throw Exception('Directorio no encontrado');
    }

    String finalRelativePath = normalizedPath;
    String finalName =
        normalizedPath.isEmpty ? 'Raíz' : path.basename(directory.path);

    if (newName != null && newName.trim().isNotEmpty) {
      if (normalizedPath.isEmpty) {
        throw Exception('No se puede renombrar la carpeta raíz');
      }

      final trimmedName = newName.trim();
      final segments =
          normalizedPath.split('/').where((segment) => segment.isNotEmpty).toList();
      final currentName = segments.removeLast();

      if (trimmedName != currentName) {
        final parentRel = segments.join('/');
        final parentAbsPath =
            parentRel.isNotEmpty ? path.join(dirsDir.path, parentRel) : dirsDir.path;

        String candidateName = trimmedName;
        Directory candidateDir =
            Directory(path.join(parentAbsPath, candidateName));
        int counter = 1;
        while (await candidateDir.exists()) {
          candidateName = '$trimmedName ($counter)';
          candidateDir = Directory(path.join(parentAbsPath, candidateName));
          counter++;
        }

        await directory.rename(candidateDir.path);
        directory = candidateDir;
        finalRelativePath =
            parentRel.isNotEmpty ? '$parentRel/$candidateName' : candidateName;
        finalName = candidateName;
      }
    } else if (normalizedPath.isNotEmpty) {
      finalName = path.basename(directory.path);
    }

    final meta = await readDirMeta(directory);
    if (colorHex != null) {
      meta['color'] = colorHex;
      await writeDirMeta(directory, meta);
    }
    final appliedColor = (colorHex ?? meta['color']) as String?;

    return {
      'path': finalRelativePath,
      'name': finalName,
      'color': appliedColor,
    };
  }

  /// Moves a document (file) locally within the user's documents directory.
  /// `sourceRelPath`: ruta relativa del archivo (ej. 'subcarpeta/archivo.pdf' o 'archivo.pdf').
  /// `newParentRelPath`: ruta relativa del nuevo padre ('' o null = raíz).
  /// Devuelve la nueva ruta relativa del archivo movido.
  static Future<String> moveDocument(String userId, String sourceRelPath, String? newParentRelPath) async {
    try {
      final docsDir = await getDocumentsDir(userId);

      // Ruta absoluta del origen
      final sourceAbsPath = path.join(docsDir.path, sourceRelPath);
      final sourceFile = File(sourceAbsPath);

      if (!await sourceFile.exists()) {
        throw Exception('Archivo no encontrado');
      }

      final fileName = path.basename(sourceRelPath);

      // Nuevo padre absoluto
      final destParentAbsPath = (newParentRelPath != null && newParentRelPath.isNotEmpty)
          ? path.join(docsDir.path, newParentRelPath)
          : docsDir.path;

      // Asegurar directorio destino
      final destParentDir = Directory(destParentAbsPath);
      if (!await destParentDir.exists()) {
        await destParentDir.create(recursive: true);
      }

      // Ruta destino final
      String destAbsPath = path.join(destParentAbsPath, fileName);
      var destFile = File(destAbsPath);

      // Evitar colisión: si ya existe, generar nombre único
      if (await destFile.exists()) {
        int counter = 1;
        final nameNoExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        String uniqueName = fileName;
        File finalDestFile = destFile;

        while (await finalDestFile.exists()) {
          uniqueName = '$nameNoExt ($counter)$ext';
          final newDestAbsPath = path.join(destParentAbsPath, uniqueName);
          finalDestFile = File(newDestAbsPath);
          counter++;
        }

        await sourceFile.rename(finalDestFile.path);

        // Nueva ruta relativa
        return (newParentRelPath != null && newParentRelPath.isNotEmpty)
            ? '$newParentRelPath/$uniqueName'
            : uniqueName;
      }

      // Mover sin colisión
      await sourceFile.rename(destAbsPath);

      return (newParentRelPath != null && newParentRelPath.isNotEmpty)
          ? '$newParentRelPath/$fileName'
          : fileName;
    } catch (e) {
      throw Exception('Error al mover documento: ${e.toString()}');
    }
  }

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    /// Renames a document locally and returns the new relative path.
  static Future<String> renameDocument(
      String userId, String sourceRelPath, String newName) async {
    final docsDir = await getDocumentsDir(userId);
    final normalizedSource = sourceRelPath.trim();
    if (normalizedSource.isEmpty) {
      throw Exception('Ruta de documento inválida');
    }

    final sourceAbsPath = path.join(docsDir.path, normalizedSource);
    final sourceFile = File(sourceAbsPath);
    if (!await sourceFile.exists()) {
      throw Exception('Archivo no encontrado');
    }

    final sanitizedName = path.basename(newName.trim());
    if (sanitizedName.isEmpty) {
      throw Exception('Nombre de documento inválido');
    }

    final segments =
        normalizedSource.split('/').where((segment) => segment.isNotEmpty).toList();
    final parentRel =
        segments.length > 1 ? segments.sublist(0, segments.length - 1).join('/') : '';
    final parentAbsPath =
        parentRel.isNotEmpty ? path.join(docsDir.path, parentRel) : docsDir.path;

    File candidateFile = File(path.join(parentAbsPath, sanitizedName));
    if (candidateFile.path == sourceFile.path) {
      return normalizedSource;
    }

    final baseName = path.basenameWithoutExtension(sanitizedName);
    final ext = path.extension(sanitizedName);
    int counter = 1;
    while (await candidateFile.exists()) {
      candidateFile = File(path.join(
          parentAbsPath, '$baseName ($counter)$ext'));
      counter++;
    }

    await sourceFile.rename(candidateFile.path);
    final newNameResult = path.basename(candidateFile.path);
    return parentRel.isNotEmpty ? '$parentRel/$newNameResult' : newNameResult;
  }

  /// Reads a file content
  static Future<String?> readFileContent(String userId, String fileName, String? relativePath) async {
    try {
      final docsDir = await getDocumentsDir(userId);
      final filePath = relativePath != null && relativePath.isNotEmpty
          ? path.join(docsDir.path, relativePath, fileName)
          : path.join(docsDir.path, fileName);
      
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Reads directory metadata (color, etc.)
  static Future<Map<String, dynamic>> readDirMeta(Directory dir) async {
    try {
      final metaFile = File(path.join(dir.path, '.dirmeta.json'));
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (e) {
      // Ignore errors reading metadata
    }
    return {};
  }

  /// Writes directory metadata (color, etc.)
  static Future<void> writeDirMeta(Directory dir, Map<String, dynamic> meta) async {
    try {
      final metaFile = File(path.join(dir.path, '.dirmeta.json'));
      await metaFile.writeAsString(
        jsonEncode(meta),
        encoding: utf8,
      );
    } catch (e) {
      // Ignore errors writing metadata
    }
  }

  /// Builds a directory tree structure similar to backend's listDirectoryNode
  static Future<Map<String, dynamic>> buildDirectoryTree(String userId, String? relativePath) async {
    final dirsDir = await getDirectoriesDir(userId);
    final targetDir = relativePath != null && relativePath.isNotEmpty
        ? Directory(path.join(dirsDir.path, relativePath))
        : dirsDir;
    
    if (!await targetDir.exists()) {
      return {
        'name': relativePath == null || relativePath.isEmpty ? 'Raíz' : path.basename(targetDir.path),
        'path': relativePath ?? '',
        'color': null,
        'directories': [],
      };
    }

    final meta = await readDirMeta(targetDir);
    final dirName = relativePath == null || relativePath.isEmpty
        ? 'Raíz'
        : path.basename(targetDir.path);
    
    final node = <String, dynamic>{
      'name': dirName,
      'path': relativePath ?? '',
      'color': meta['color'],
      'directories': <Map<String, dynamic>>[],
    };

    try {
      final items = targetDir.listSync();
      for (final item in items) {
        if (item is Directory) {
          final itemName = path.basename(item.path);
          // Skip hidden directories
          if (itemName.startsWith('.')) continue;
          
          final itemRelPath = relativePath != null && relativePath.isNotEmpty
              ? '$relativePath/$itemName'
              : itemName;
          
          final childNode = await buildDirectoryTree(userId, itemRelPath);
          (node['directories'] as List).add(childNode);
        }
      }
    } catch (e) {
      // Ignore errors listing directory
    }

    return node;
  }
 
  /// Copies a document (file) locally within the user's documents directory.
  /// `sourceRelPath`: ruta relativa del archivo (ej. 'subcarpeta/archivo.pdf' o 'archivo.pdf').
  /// `newParentRelPath`: ruta relativa del nuevo padre ('' o null = raíz).
  /// Devuelve la nueva ruta relativa del archivo copiado.
  static Future<String> copyDocument(String userId, String sourceRelPath, String? newParentRelPath) async {
    try {
      final docsDir = await getDocumentsDir(userId);

      // Ruta absoluta del origen
      final sourceAbsPath = path.join(docsDir.path, sourceRelPath);
      final sourceFile = File(sourceAbsPath);

      if (!await sourceFile.exists()) {
        throw Exception('Archivo no encontrado');
      }

      final fileName = path.basename(sourceRelPath);

      // Nuevo padre absoluto
      final destParentAbsPath = (newParentRelPath != null && newParentRelPath.isNotEmpty)
          ? path.join(docsDir.path, newParentRelPath)
          : docsDir.path;

      // Asegurar directorio destino
      final destParentDir = Directory(destParentAbsPath);
      if (!await destParentDir.exists()) {
        await destParentDir.create(recursive: true);
      }

      // Ruta destino final
      String destAbsPath = path.join(destParentAbsPath, fileName);
      var destFile = File(destAbsPath);

      // Evitar colisión: si ya existe, generar nombre único
      if (await destFile.exists()) {
        int counter = 1;
        final nameNoExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        String uniqueName;
        File? finalDestFile;

        while (true) {
          uniqueName = '$nameNoExt ($counter)$ext';
          final newDestAbsPath = path.join(destParentAbsPath, uniqueName);
          finalDestFile = File(newDestAbsPath);
          if (!await finalDestFile.exists()) break;
          counter++;
        }

        await sourceFile.copy(finalDestFile.path);

        // Nueva ruta relativa
        return (newParentRelPath != null && newParentRelPath.isNotEmpty)
            ? '$newParentRelPath/$uniqueName'
            : uniqueName;
      }

      // Copiar sin colisión
      await sourceFile.copy(destAbsPath);

      return (newParentRelPath != null && newParentRelPath.isNotEmpty)
          ? '$newParentRelPath/$fileName'
          : fileName;
    } catch (e) {
      throw Exception('Error al copiar documento: ${e.toString()}');
    }
  }

  /// Scans a local directory tree and returns all items for upload to server
  /// Returns a list of maps with structure: {type, path, name, content (base64 for files)}
  static Future<List<Map<String, dynamic>>> scanDirectoryTree(
      String userId, String folderRelativePath) async {
    final items = <Map<String, dynamic>>[];
    
    try {
      final dirsDir = await getDirectoriesDir(userId);
      final docsDir = await getDocumentsDir(userId);
      
      // Scan directories tree
      final dirPath = path.join(dirsDir.path, folderRelativePath);
      final directory = Directory(dirPath);
      
      if (!await directory.exists()) {
        throw Exception('Directory does not exist: $folderRelativePath');
      }
      
      // Recursive function to scan directory
      Future<void> scanDir(Directory dir, String relativePath) async {
        // Add directory itself
        if (relativePath != folderRelativePath) {
          items.add({
            'type': 'directory',
            'path': relativePath,
            'name': path.basename(relativePath),
          });
        }
        
        final entities = await dir.list().toList();
        
        for (final entity in entities) {
          if (entity is Directory) {
            // Recursively scan subdirectories
            final subRelPath = path.join(
              relativePath,
              path.basename(entity.path)
            );
            await scanDir(entity, subRelPath);
          } else if (entity is File) {
            // Skip metadata files
            if (path.basename(entity.path) == '.dirmeta.json') continue;
            
            // This is a file in directories folder (shouldn't happen, but skip)
            continue;
          }
        }
      }
      
      // Start scanning from root folder
      await scanDir(directory, folderRelativePath);
      
      // Now scan for documents in the same relative path structure
      final docsFolderPath = path.join(docsDir.path, folderRelativePath);
      final docsFolder = Directory(docsFolderPath);
      
      if (await docsFolder.exists()) {
        Future<void> scanDocs(Directory dir, String relativePath) async {
          final entities = await dir.list().toList();
          
          for (final entity in entities) {
            if (entity is Directory) {
              // Recursively scan subdirectories
              final subRelPath = path.join(
                relativePath,
                path.basename(entity.path)
              );
              await scanDocs(entity, subRelPath);
            } else if (entity is File) {
              // Read file and encode as base64
              final fileBytes = await entity.readAsBytes();
              final base64Content = base64Encode(fileBytes);
              
              final fileRelPath = path.join(
                relativePath,
                path.basename(entity.path)
              );
              
              items.add({
                'type': 'file',
                'path': fileRelPath,
                'name': path.basename(entity.path),
                'content': base64Content,
              });
            }
          }
        }
        
        await scanDocs(docsFolder, folderRelativePath);
      }
      
      return items;
    } catch (e) {
      throw Exception('Error scanning directory tree: ${e.toString()}');
    }
  }

  /// Returns all subdirectory relative paths under the given folder (including nested),
  /// relative to the user's directories root. Does not include the root folder itself.
  static Future<List<String>> scanDirectoryStructure(
      String userId, String folderRelativePath) async {
    final results = <String>[];
    final dirsRoot = await getDirectoriesDir(userId);
    final rootPath = path.join(dirsRoot.path, folderRelativePath);
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return results;

    Future<void> walk(Directory dir, String rel) async {
      final entries = await dir.list().toList();
      for (final e in entries) {
        if (e is Directory) {
          final subRel = path.join(rel, path.basename(e.path));
          results.add(subRel);
          await walk(e, subRel);
        }
      }
    }

    await walk(rootDir, folderRelativePath);
    return results;
  }

  /// Lists all files (PDF, TXT, etc.) in the documents tree under folderRelativePath.
  /// Returns a list of maps: { path, name, ext, size }
  static Future<List<Map<String, dynamic>>> listFilesInTree(
      String userId, String folderRelativePath) async {
    final files = <Map<String, dynamic>>[];
    final docsRoot = await getDocumentsDir(userId);
    final basePath = path.join(docsRoot.path, folderRelativePath);
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) return files;

    Future<void> walk(Directory dir, String rel) async {
      final entries = await dir.list().toList();
      for (final e in entries) {
        if (e is Directory) {
          final subRel = path.join(rel, path.basename(e.path));
          await walk(e, subRel);
        } else if (e is File) {
          final stat = await e.stat();
          files.add({
            'path': path.join(rel, path.basename(e.path)),
            'name': path.basename(e.path),
            'ext': path.extension(e.path).replaceFirst('.', '').toLowerCase(),
            'size': stat.size,
          });
        }
      }
    }

    await walk(baseDir, folderRelativePath);
    return files;
  }

  /// Reads a file from the documents tree and returns its Base64-encoded content
  static Future<String> readDocsFileAsBase64(
      String userId, String relativeFilePath) async {
    final docsRoot = await getDocumentsDir(userId);
    final abs = path.join(docsRoot.path, relativeFilePath);
    final f = File(abs);
    final bytes = await f.readAsBytes();
    return base64Encode(bytes);
  }
}
