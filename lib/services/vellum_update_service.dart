import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Default update/download repository (Gitee).
const vellumDefaultRepository = 'gitee.com/Murchey/vellum';
const vellumDefaultRepositoryUrl = 'https://gitee.com/Murchey/vellum';

/// Parsed remote repository reference.
class RepoRef {
  const RepoRef({
    required this.host,
    required this.owner,
    required this.repo,
  });

  /// e.g. `gitee.com` or `github.com`
  final String host;
  final String owner;
  final String repo;

  String get slug => '$owner/$repo';
  bool get isGitee => host == 'gitee.com';

  String get webUrl => 'https://$host/$owner/$repo';

  String get latestReleaseApi => isGitee
      ? 'https://gitee.com/api/v5/repos/$owner/$repo/releases/latest'
      : 'https://api.github.com/repos/$owner/$repo/releases/latest';

  @override
  String toString() => '$host/$owner/$repo';
}

/// Parses `owner/repo`, `gitee.com/owner/repo`, or a full https URL.
/// Bare `owner/repo` is treated as Gitee (the default host).
RepoRef? parseUpdateRepository(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  value = value.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  value = value.replaceAll(RegExp(r'/+$'), '');

  var host = 'gitee.com';
  if (value.toLowerCase().startsWith('github.com/')) {
    host = 'github.com';
    value = value.substring('github.com/'.length);
  } else if (value.toLowerCase().startsWith('gitee.com/')) {
    value = value.substring('gitee.com/'.length);
  }

  final parts = value.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return RepoRef(host: host, owner: parts[0], repo: parts[1]);
}

/// Display label, e.g. `gitee.com/Murchey/vellum`.
String? normalizeUpdateRepository(String input) =>
    parseUpdateRepository(input)?.toString();

class VellumReleaseInfo {
  const VellumReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.notes,
    required this.releaseUrl,
    required this.assets,
    this.repository = vellumDefaultRepository,
  });

  final String currentVersion;
  final String latestVersion;
  final String notes;
  final String releaseUrl;
  final Map<String, String> assets;

  /// Same source used for detection and download links.
  final String repository;

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

  /// Checks the configured repository (Gitee or GitHub).
  /// Empty/null uses the built-in default (Gitee).
  Future<VellumReleaseInfo?> check({String? repository}) async {
    final ref =
        parseUpdateRepository(repository ?? '') ??
        parseUpdateRepository(vellumDefaultRepository)!;
    final package = await PackageInfo.fromPlatform();
    final response = await http
        .get(
          Uri.parse(ref.latestReleaseApi),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    final assets = <String, String>{};
    for (final value in data['assets'] as List<dynamic>? ?? const []) {
      final asset = value as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      final url =
          (asset['browser_download_url'] as String?) ??
          (asset['download_url'] as String?) ??
          '';
      if (name.toLowerCase().endsWith('.apk') && url.isNotEmpty) {
        assets[name] = url;
      }
    }
    final htmlUrl = data['html_url'] as String? ?? ref.webUrl;
    return VellumReleaseInfo(
      currentVersion: package.version,
      latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: data['body'] as String? ?? '',
      releaseUrl: htmlUrl,
      assets: assets,
      repository: ref.toString(),
    );
  }
}
