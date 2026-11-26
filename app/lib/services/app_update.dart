import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';

/// Server-driven rollout policy for the in-app update curtain.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latest,
    required this.minimum,
    required this.force,
    required this.message,
  });

  final String latest;
  final String minimum;
  final bool force;
  final String message;
}

/// Strict semver comparison. `0.5.92+102` compares as `0.5.92`; build number
/// is intentionally ignored because the worker publishes product versions,
/// while Play versionCodes are an upload-account concern.
int compareAppVersions(String a, String b) {
  List<int> parts(String v) {
    final cleaned = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final raw = cleaned.split('.');
    return List<int>.generate(3, (i) => i < raw.length ? int.tryParse(raw[i]) ?? 0 : 0);
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Reads the version Google Play publishes in its public listing. The listing
/// HTML carries the app's own version in a small `[[["0.5.96"]]]` array; it is
/// not a Formula error, just Play's compact data encoding. Returns null when
/// Play is unreachable or the shape changes — our server policy still works.
String? parsePlayStoreVersion(String html) {
  final m = RegExp(r'\[\[\["(\d+\.\d+\.\d+(?:\.\d+)?)"\]\]+').firstMatch(html);
  if (m == null) return null;
  final v = m.group(1);
  return (v != null && compareAppVersions(v, '0.0.1') > 0) ? v : null;
}

class AppUpdateService {
  const AppUpdateService._();

  /// Play's own published version (never blocks startup on failure).
  static Future<String?> playStoreVersion() async {
    try {
      final r = await http.get(
        Uri.parse('https://play.google.com/store/apps/details?id=zm.dropoff.dropoff&hl=en_US&gl=US'),
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return parsePlayStoreVersion(r.body);
    } catch (_) {
      return null;
    }
  }

  static Future<AppUpdateInfo?> _fetch() async {
    for (final base in [DropOffApi.baseUrl, DropOffApi.fallbackBaseUrl]) {
      try {
        final r = await http.get(Uri.parse('$base/app/version')).timeout(const Duration(seconds: 7));
        if (r.statusCode != 200) continue;
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        return AppUpdateInfo(
          latest: '${data['latest'] ?? '0.6.0'}',
          minimum: '${data['minimum'] ?? '0.5.0'}',
          force: data['force'] == true,
          message: '${data['message'] ?? 'A faster, smoother DropOff is ready.'}',
        );
      } catch (_) {
        // Try the second front door. An offline launch must never be blocked
        // by the update check.
      }
    }
    return null;
  }

  static Future<void> checkAndShow(BuildContext context) async {
    // Check BOTH our policy endpoint and the live Play listing: Play can have a
    // newer build than the rollout note, and a "Download" must always mean the
    // version actually published on the Store.
    final results = await Future.wait([_fetch(), playStoreVersion()]);
    AppUpdateInfo? info = results[0] as AppUpdateInfo?;
    final play = results[1] as String?;
    if (play != null && (info == null || compareAppVersions(play, info.latest) > 0)) {
      info = AppUpdateInfo(
        latest: play,
        minimum: info?.minimum ?? '0.5.0',
        force: info?.force ?? false,
        message: info?.message ?? 'A faster, smoother DropOff is ready.',
      );
    }
    final effective = info;
    if (effective == null || !context.mounted) return;
    PackageInfo pkg;
    try {
      pkg = await PackageInfo.fromPlatform();
    } catch (_) {
      return; // unsupported platform / test harness
    }
    final current = pkg.version;
    if (compareAppVersions(current, effective.latest) >= 0) return;
    if (!context.mounted) return;

    final required = compareAppVersions(current, effective.minimum) < 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: !required && !effective.force,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => AppUpdateCurtain(info: effective, required: required || effective.force),
    );
  }

  static Future<void> openStore({required String latest}) async {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final primary = isAndroid
        ? Uri.parse('market://details?id=zm.dropoff.dropoff')
        : Uri.parse('https://play.google.com/store/apps/details?id=zm.dropoff.dropoff');
    final fallback = Uri.parse('https://dropoff.carpsosolutions.store');
    try {
      if (await launchUrl(primary, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Play Store missing (emulator, sideload, web) -> try web Play then PWA.
    }
    try {
      if (await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=zm.dropoff.dropoff'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // PWA is the last working front door.
    }
    await launchUrl(fallback, mode: LaunchMode.externalApplication);
  }
}

/// Full-screen, premium update curtain — the same visual language as the
/// incoming-order answer card, not a stock Android dialog.
class AppUpdateCurtain extends StatelessWidget {
  const AppUpdateCurtain({super.key, required this.info, required this.required});

  final AppUpdateInfo info;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: !required,
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.forest, Color(0xFF071F19)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, media.padding.top + 22, 24, media.padding.bottom + 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: media.size.height - media.padding.top - media.padding.bottom - 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: (required ? AppColors.amber : AppColors.forestLight).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          required ? 'UPDATE REQUIRED' : 'A NEW DROPOFF IS HERE',
                          style: const TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset('assets/brand/dropoff_logo.png', width: 108, height: 108),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Keep every delivery moving.',
                      style: TextStyle(color: Colors.white, fontSize: 30, height: 1.12, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      info.message,
                      style: const TextStyle(color: Color(0xFFD7E5E0), fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    const _UpdateBenefit(icon: Icons.route_outlined, text: 'Smoother, more reliable maps'),
                    const _UpdateBenefit(icon: Icons.receipt_long_outlined, text: 'Receipts that open when payment lands'),
                    const _UpdateBenefit(icon: Icons.my_location_outlined, text: 'Exact pickup pins and faster dispatch'),
                    const SizedBox(height: 32),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.amber,
                          foregroundColor: AppColors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: Text('Update DropOff  ·  ${info.latest}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        onPressed: () => AppUpdateService.openStore(latest: info.latest),
                      ),
                    ),
                    if (!required)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Not now', style: TextStyle(color: Color(0xFFBFD2CB))),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'DropOff  ·  Carpso Solutions  ·  0968551110',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF78958B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateBenefit extends StatelessWidget {
  const _UpdateBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.amber, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
