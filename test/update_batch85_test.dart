import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/update/auto_updater.dart';

/// Batch 85: update checks bind to Anikumo's own GitHub
/// repository (xyu3032-commits/Anikumo) instead of the
/// upstream project. The release-payload parsing and the
/// asset picking are pure and pinned here.
void main() {
  Map<String, dynamic> release({
    String tag = 'v1.0.1',
    List<dynamic>? assets,
  }) =>
      {
        'tag_name': tag,
        'name': '第二十二版',
        'body': '修复若干问题',
        'html_url':
            'https://github.com/xyu3032-commits/Anikumo/releases/tag/v1.0.1',
        'published_at': '2026-11-09T00:00:00Z',
        'assets': assets ??
            [
              {
                'name': 'anikumo_v22_arm64.apk',
                'browser_download_url': 'https://x/arm64.apk',
              },
              {
                'name': 'anikumo_v22_v7a.apk',
                'browser_download_url': 'https://x/v7a.apk',
              },
            ],
      };

  group('AutoUpdater.parseGithubRelease', () {
    test('a newer v-prefixed tag becomes an UpdateInfo', () {
      final info = AutoUpdater.parseGithubRelease(
        release(),
        localVersion: '1.0.0',
        types: const [InstallationType.androidApk],
      );
      expect(info, isNotNull);
      expect(info!.version, '1.0.1');
      expect(info.description, '第二十二版');
      expect(info.releaseNotes, '修复若干问题');
      expect(info.downloadUrl, contains('/releases/tag/v1.0.1'));
      expect(info.assets, hasLength(2));
    });

    test('same or older versions are not updates', () {
      expect(
        AutoUpdater.parseGithubRelease(
          release(tag: 'v1.0.0'),
          localVersion: '1.0.0',
          types: const [InstallationType.androidApk],
        ),
        isNull,
      );
      expect(
        AutoUpdater.parseGithubRelease(
          release(tag: '0.9.9'),
          localVersion: '1.0.0',
          types: const [InstallationType.androidApk],
        ),
        isNull,
      );
    });

    test('non-version tags are ignored instead of throwing', () {
      expect(
        AutoUpdater.parseGithubRelease(
          release(tag: 'nightly-2026'),
          localVersion: '1.0.0',
          types: const [InstallationType.androidApk],
        ),
        isNull,
      );
      expect(
        AutoUpdater.parseGithubRelease(
          const {},
          localVersion: '1.0.0',
          types: const [InstallationType.androidApk],
        ),
        isNull,
      );
    });
  });

  group('APK asset picking', () {
    test('prefers the arm64 split among our release assets', () {
      final assets = release()['assets'] as List<dynamic>;
      final picked =
          getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(picked?['name'], 'anikumo_v22_arm64.apk');
    });

    test('no apk asset means no in-app download', () {
      final picked = getUpdateAssetForType(
        [
          {'name': 'notes.txt'},
        ],
        InstallationType.androidApk,
      );
      expect(picked, isNull);
      expect(InstallationType.androidApk.downloadsInApp, isTrue);
    });
  });

  test('the feed is the Anikumo repository, not upstream', () {
    expect(
      AutoUpdater.releasesApiUrl,
      'https://api.github.com/repos/xyu3032-commits/Anikumo/releases/latest',
    );
    expect(AutoUpdater.releasesPageUrl,
        'https://github.com/xyu3032-commits/Anikumo/releases');
  });
}
