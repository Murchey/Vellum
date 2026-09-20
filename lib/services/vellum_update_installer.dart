import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'vellum_update_service.dart';

class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Bridges the update flow to the platform: supported ABIs, APK download and
/// handing the file to the system package installer.
class VellumUpdateInstaller {
  const VellumUpdateInstaller();

  static const _channel = MethodChannel('vellum/device');
  static const _userAgent = {'User-Agent': 'Vellum-App'};

  /// Only Android can install a downloaded APK in place.
  bool get canInstallInApp => Platform.isAndroid;

  /// First supported ABI of this device that we have a label for, or null.
  Future<String?> deviceAbi() async {
    if (!Platform.isAndroid) return null;
    try {
      final abis = await _channel.invokeMethod<List<dynamic>>('supportedAbis');
      for (final abi in abis ?? const <dynamic>[]) {
        if (abi is! String) continue;
        final normalized = normalizeAbiName(abi);
        if (normalized != null) return normalized;
      }
    } catch (_) {
      // Missing plugin or an older shell: fall back to the default ordering.
    }
    return null;
  }

  /// Whether the user has allowed installing apps from this source.
  Future<bool> canRequestInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    } catch (_) {
      // Unknown: let the installer itself decide.
      return true;
    }
  }

  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  /// Streams [asset] into the app's private `updates/` directory.
  ///
  /// Returns the downloaded file; partial downloads are removed when
  /// [isCancelled] turns true.
  Future<File> download(
    UpdateApkAsset asset, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}updates',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_safeFileName(asset.name)}',
    );
    if (await file.exists()) await file.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(asset.url))
        ..headers.addAll(_userAgent);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw ApkDownloadException('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (isCancelled?.call() ?? false) {
            throw const ApkDownloadException('已取消下载。');
          }
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total != null && received < total) {
        throw const ApkDownloadException('下载未完成，请检查网络后重试。');
      }
      return file;
    } catch (error) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Hands [apk] to the system installer.
  Future<void> install(File apk) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    } on PlatformException catch (error) {
      throw ApkDownloadException(error.message ?? '无法调起安装器。');
    } on MissingPluginException {
      throw const ApkDownloadException('当前平台不支持应用内安装。');
    }
  }

  String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'vellum-update.apk' : cleaned;
  }
}