import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const vellumGitHubRepository = 'niriko-mu/Vellum';
const vellumGitHubRepositoryUrl = 'https://github.com/niriko-mu/Vellum';

/// Normalizes `owner/repo` or a GitHub repository URL to `owner/repo`.
String? normalizeGitHubRepository(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'^github\.com/', caseSensitive: false), '');
  value = value.replaceAll(RegExp(r'/+$'), '');
  final parts = value.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return '${parts[0]}/${parts[1]}';
}

class VellumReleaseInfo {
  const VellumReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.notes,
    required this.releaseUrl,
    required this.assets,
  });

  final String currentVersion;
  final String latestVersion;
  final String notes;
  final String releaseUrl;
  final Map<String, String> assets;

  bool get hasUpdate => _isNewer(latestVersion, currentVersion);

  static bool _isNewer(String latest, String current) {
    List<int> parse(String value) => value
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final remote = parse(latest);
    final local = parse(current);
    final length = remote.length > local.length ? remote.length : local.length;
    for (var index = 0; index < length; index++) {
      final a = index < remote.length ? remote[index] : 0;
      final b = index < local.length ? local[index] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}

class VellumUpdateService {
  const VellumUpdateService();

  /// Checks GitHub Releases for [repository] (`owner/repo`).
  /// Empty/null uses the built-in default repository.
  Future<VellumReleaseInfo?> check({String? repository}) async {
    final slug = normalizeGitHubRepository(repository ?? '') ??
        vellumGitHubRepository;
    final package = await PackageInfo.fromPlatform();
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$slug/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    final assets = <String, String>{};
    for (final value in data['assets'] as List<dynamic>? ?? const []) {
      final asset = value as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String? ?? '';
      if (name.endsWith('.apk') && url.isNotEmpty) assets[name] = url;
    }
    final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$slug';
    return VellumReleaseInfo(
      currentVersion: package.version,
      latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: data['body'] as String? ?? '',
      releaseUrl: htmlUrl,
      assets: assets,
    );
  }
}
