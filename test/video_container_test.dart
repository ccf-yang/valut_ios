import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:vault/core/models.dart';
import 'package:vault/state/upload_providers.dart';

AssetEntity _asset(String id, {required bool video, required DateTime created}) => AssetEntity(
      id: id,
      typeInt: video ? 2 : 1,
      width: 100,
      height: 100,
      duration: video ? 95 : 0,
      createDateSecond: created.millisecondsSinceEpoch ~/ 1000,
    );

RemoteEntry _video(String name) => RemoteEntry(name: name, path: '/aliyun/$name', isDir: false);

void main() {
  group('视频按容器分流到哪个播放器', () {
    test('Apple 原生能解的容器留在 AVPlayer', () {
      for (final name in ['a.mp4', 'b.mov', 'c.m4v', 'd.3gp', 'e.ts']) {
        final entry = _video(name);
        expect(entry.kind, FileKind.video, reason: name);
        expect(entry.isNativePlayableVideo, isTrue, reason: name);
        expect(entry.needsMpvPlayback, isFalse, reason: name);
      }
    });

    // AVPlayer 不做这些容器的解封装：不是拖不动，是打开就失败，所以必须换播放器。
    test('mkv 等非 Apple 容器走 libmpv', () {
      for (final name in ['a.mkv', 'b.webm', 'c.avi', 'd.flv', 'e.wmv', 'f.rmvb', 'g.mpg', 'h.vob', 'i.MKV']) {
        final entry = _video(name);
        expect(entry.kind, FileKind.video, reason: name);
        expect(entry.needsMpvPlayback, isTrue, reason: name);
        expect(entry.isNativePlayableVideo, isFalse, reason: name);
      }
    });

    test('图片和音频不归视频播放器管', () {
      expect(_video('a.jpg').needsMpvPlayback, isFalse);
      expect(_video('a.mp3').needsMpvPlayback, isFalse);
    });

    test('没有扩展名不当成视频', () {
      expect(_video('noext').kind, isNot(FileKind.video));
    });
  });

  group('上传的按天选择包含视频', () {
    final today = DateTime(2026, 10, 10, 9);
    final yesterday = DateTime(2026, 10, 9, 20);

    test('最近 1 天 = 今天，照片和视频一起进来', () {
      final assets = [
        _asset('v1', video: true, created: today),
        _asset('p1', video: false, created: today),
        _asset('p2', video: false, created: yesterday),
      ];
      final picked = withinRecentDays(assets, 1, now: today);
      expect(picked.map((a) => a.id), containsAll(['v1', 'p1']));
      expect(picked.map((a) => a.id), isNot(contains('p2')));
    });

    test('最近 2 天把昨天的也带上', () {
      final assets = [
        _asset('v1', video: true, created: today),
        _asset('p2', video: false, created: yesterday),
      ];
      expect(withinRecentDays(assets, 2, now: today), hasLength(2));
    });

    test('分桶按创建日期，视频落在自己那天的桶里', () {
      final buckets = groupByDay([
        _asset('v1', video: true, created: today),
        _asset('p1', video: false, created: today),
        _asset('p2', video: false, created: yesterday),
      ]);
      expect(buckets, hasLength(2));
      expect(buckets.first.day, DateTime(2026, 10, 10));
      expect(buckets.first.assets.where((a) => a.type == AssetType.video), hasLength(1));
    });
  });
}
