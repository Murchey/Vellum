import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'backup_crypto.dart';
import 'cos_auth.dart';

/// Credentials are kept in the platform secure store. They are never part of
/// a Vellum backup archive or a user-visible error message.
class VellumCloudConfig {
  const VellumCloudConfig({
    this.secretId = '',
    this.secretKey = '',
    this.bucketUrl = '',
    this.prefix = 'vellum/backups/v1',
  });

  final String secretId;
  final String secretKey;
  final String bucketUrl;
  final String prefix;

  String get host {
    var value = bucketUrl.trim().replaceAll(RegExp(r'/+$'), '');
    value = value.replaceFirst(RegExp(r'^https?://'), '');
    return value.split('/').first.split('?').first.split('#').first;
  }

  String get scheme =>
      bucketUrl.trim().toLowerCase().startsWith('http://') ? 'http' : 'https';

  bool get isConfigured =>
      secretId.trim().isNotEmpty &&
      secretKey.trim().isNotEmpty &&
      host.isNotEmpty &&
      detectCosVendor(host) != CosVendor.other;

  String get vendorLabel => switch (detectCosVendor(host)) {
    CosVendor.tencent => '腾讯云 COS',
    CosVendor.aliyun => '阿里云 OSS',
    CosVendor.other => '未知对象存储',
  };

  String get normalizedPrefix {
    final value = prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return value.isEmpty ? 'vellum/backups/v1' : value;
  }

  VellumCloudConfig copyWith({
    String? secretId,
    String? secretKey,
    String? bucketUrl,
    String? prefix,
  }) => VellumCloudConfig(
    secretId: secretId ?? this.secretId,
    secretKey: secretKey ?? this.secretKey,
    bucketUrl: bucketUrl ?? this.bucketUrl,
    prefix: prefix ?? this.prefix,
  );
}

class VellumBackupItem {
  const VellumBackupItem({
    required this.file,
    required this.size,
    required this.modified,
  });

  final File file;
  final int size;
  final DateTime modified;
}

class VellumCloudBackupObject {
  const VellumCloudBackupObject({
    required this.key,
    required this.size,
    required this.lastModified,
  });

  final String key;
  final int size;
  final DateTime? lastModified;

  String get fileName => key.split('/').last;
}

class VellumBackupService {
  VellumBackupService({
    FlutterSecureStorage? secureStorage,
    http.Client? client,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client();

  static const _cloudIdKey = 'vellum_cloud_secret_id';
  static const _cloudKeyKey = 'vellum_cloud_secret_key';
  static const _cloudBucketKey = 'vellum_cloud_bucket_url';
  static const _cloudPrefixKey = 'vellum_cloud_prefix';
  static const _manifest = 'vellum_manifest.json';

  final FlutterSecureStorage _secureStorage;
  final http.Client _client;

  Future<Directory> _documents() => getApplicationDocumentsDirectory();

  Future<Directory> localBackupDirectory() async {
    final docs = await _documents();
    final dir = Directory('${docs.path}${Platform.pathSeparator}backups');
    await dir.create(recursive: true);
    return dir;
  }

  Future<VellumCloudConfig> loadCloudConfig() async {
    return VellumCloudConfig(
      secretId: await _secureStorage.read(key: _cloudIdKey) ?? '',
      secretKey: await _secureStorage.read(key: _cloudKeyKey) ?? '',
      bucketUrl: await _secureStorage.read(key: _cloudBucketKey) ?? '',
      prefix:
          await _secureStorage.read(key: _cloudPrefixKey) ??
          'vellum/backups/v1',
    );
  }

  Future<void> saveCloudConfig(VellumCloudConfig config) async {
    final values = <String, String>{
      _cloudIdKey: config.secretId.trim(),
      _cloudKeyKey: config.secretKey.trim(),
      _cloudBucketKey: config.bucketUrl.trim(),
      _cloudPrefixKey: config.normalizedPrefix,
    };
    for (final entry in values.entries) {
      if (entry.value.isEmpty) {
        await _secureStorage.delete(key: entry.key);
      } else {
        await _secureStorage.write(key: entry.key, value: entry.value);
      }
    }
  }

  Future<Uint8List> exportArchive({String? password}) async {
    final docs = await _documents();
    final archive = Archive();
    final info = await PackageInfo.fromPlatform();
    archive.addFile(
      ArchiveFile.string(
        _manifest,
        const JsonEncoder.withIndent('  ').convert({
          'app': 'Vellum',
          'format': 1,
          'version': info.version,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    );
    if (await docs.exists()) {
      await for (final entity in docs.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = _relative(entity.path, docs.path);
        if (relative == null || _isExcluded(relative)) continue;
        archive.addFile(
          ArchiveFile.bytes('files/$relative', await entity.readAsBytes()),
        );
      }
    }
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    return password == null || password.isEmpty
        ? zip
        : BackupCrypto.encrypt(zip, password);
  }

  Future<File> createLocalBackup({String? password}) async {
    final bytes = await exportArchive(password: password);
    final dir = await localBackupDirectory();
    final suffix = password == null || password.isEmpty ? 'zip' : 'vbackup';
    final stamp = _stamp(DateTime.now());
    final file = File(
      '${dir.path}${Platform.pathSeparator}vellum_$stamp.$suffix',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<VellumBackupItem>> listLocalBackups() async {
    final dir = await localBackupDirectory();
    final items = <VellumBackupItem>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path).toLowerCase();
      if (!name.endsWith('.zip') && !name.endsWith('.vbackup')) continue;
      items.add(
        VellumBackupItem(
          file: entity,
          size: await entity.length(),
          modified: await entity.lastModified(),
        ),
      );
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// Restores files only after validating the manifest and rejecting paths that
  /// escape the documents directory. Existing files are replaced atomically at
  /// the file level; the backup archive itself is never deleted.
  Future<void> restore(File source, {String? password}) async {
    final raw = await source.readAsBytes();
    final bytes = BackupCrypto.decrypt(raw, password ?? '');
    await _restoreBytes(bytes);
  }

  Future<void> _restoreBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile(_manifest);
    if (manifestFile == null) throw const FormatException('不是 Vellum 备份文件');
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>));
    if (manifest is! Map || manifest['app'] != 'Vellum') {
      throw const FormatException('备份文件属于其他应用');
    }
    final docs = await _documents();
    for (final item in archive.files) {
      if (!item.isFile || !item.name.startsWith('files/')) continue;
      final relative = item.name.substring('files/'.length);
      if (_isExcluded(relative) || _unsafe(relative)) continue;
      final target = File('${docs.path}${Platform.pathSeparator}$relative');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(item.content as List<int>, flush: true);
    }
  }

  Future<List<VellumCloudBackupObject>> listCloud(
    VellumCloudConfig config,
  ) async {
    if (!config.isConfigured) throw StateError('云备份配置不完整');
    final uri = Uri(
      scheme: config.scheme,
      host: config.host,
      queryParameters: {
        'prefix': '${config.normalizedPrefix}/',
        'max-keys': '100',
      },
    );
    final headers = buildCosAuthHeaders(
      method: 'GET',
      uri: uri,
      accessKeyId: config.secretId,
      secretAccessKey: config.secretKey,
    );
    final response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('读取云备份列表失败（HTTP ${response.statusCode}）');
    }
    final document = XmlDocument.parse(response.body);
    return [
      for (final key in document.findAllElements('Key'))
        if (key.innerText.trim().isNotEmpty)
          VellumCloudBackupObject(
            key: key.innerText.trim(),
            size:
                int.tryParse(
                  key.parent?.getElement('Size')?.innerText.trim() ?? '',
                ) ??
                0,
            lastModified: DateTime.tryParse(
              key.parent?.getElement('LastModified')?.innerText.trim() ?? '',
            ),
          ),
    ]..sort(
      (a, b) => (b.lastModified ?? DateTime(0)).compareTo(
        a.lastModified ?? DateTime(0),
      ),
    );
  }

  Future<Uint8List> downloadCloud(VellumCloudConfig config, String key) async {
    if (!config.isConfigured) throw StateError('云备份配置不完整');
    final uri = Uri(
      scheme: config.scheme,
      host: config.host,
      pathSegments: key.split('/'),
    );
    final headers = buildCosAuthHeaders(
      method: 'GET',
      uri: uri,
      accessKeyId: config.secretId,
      secretAccessKey: config.secretKey,
    );
    final response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('下载云备份失败（HTTP ${response.statusCode}）');
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  Future<void> restoreCloud(
    VellumCloudConfig config,
    String key, {
    String? password,
  }) async {
    final raw = await downloadCloud(config, key);
    await _restoreBytes(BackupCrypto.decrypt(raw, password ?? ''));
  }

  Future<VellumBackupItem> upload(
    VellumCloudConfig config, {
    String? password,
  }) async {
    if (!config.isConfigured) throw StateError('云备份配置不完整');
    final bytes = await exportArchive(password: password);
    final fileName = 'vellum_${_stamp(DateTime.now())}.zip';
    final key = '${config.normalizedPrefix}/$fileName';
    final uri = Uri(
      scheme: config.scheme,
      host: config.host,
      pathSegments: key.split('/'),
    );
    final headers = {
      'Content-Type': 'application/octet-stream',
      'Content-Length': '${bytes.length}',
      ...buildCosAuthHeaders(
        method: 'PUT',
        uri: uri,
        accessKeyId: config.secretId,
        secretAccessKey: config.secretKey,
        contentType: 'application/octet-stream',
      ),
    };
    final response = await _client.put(uri, headers: headers, body: bytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('云备份上传失败（HTTP ${response.statusCode}）');
    }
    final dir = await localBackupDirectory();
    final marker = File('${dir.path}${Platform.pathSeparator}$fileName');
    await marker.writeAsBytes(bytes, flush: true);
    return VellumBackupItem(
      file: marker,
      size: bytes.length,
      modified: DateTime.now(),
    );
  }

  void dispose() => _client.close();

  bool _isExcluded(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    if (normalized == _manifest || normalized.startsWith('backups/'))
      return true;
    if (normalized.startsWith('.')) return true;
    return normalized
        .split('/')
        .any((part) => part == 'cache' || part == '.dart_tool');
  }

  bool _unsafe(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    return normalized.startsWith('/') || normalized.split('/').contains('..');
  }

  String? _relative(String path, String root) {
    final normalizedPath = path.replaceAll('\\', '/');
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    if (!normalizedPath.startsWith('$normalizedRoot/')) return null;
    final value = normalizedPath.substring(normalizedRoot.length + 1);
    return _unsafe(value) ? null : value;
  }

  String _stamp(DateTime value) {
    final utc = value.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}_${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
