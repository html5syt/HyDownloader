import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hydownloader/config/app_constants.dart';
import 'package:hydownloader/models/song.dart';
import 'package:hydownloader/models/download_task.dart';
import 'package:hydownloader/services/audio/audio_duration_service.dart';
import 'package:hydownloader/services/download/download_service.dart';
import 'package:hydownloader/services/storage/storage_service.dart';
import 'package:hydownloader/services/storage/file_access.dart';

Song song(String id, {bool vip = true, int duration = 180000}) => Song(
  id: id,
  name: id,
  artists: const ['歌手'],
  albumName: '',
  albumCoverUrl: '',
  durationMs: duration,
  fee: vip ? 1 : 0,
);

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('等待状态超时');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DownloadService service;
  final gates = <String, Completer<void>>{};
  final durations = <String, int?>{};
  final runs = <String, int>{};

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefKeyMaxConcurrent: 2,
      AppConstants.prefKeyDownloadLyrics: false,
      AppConstants.prefKeyWriteMetadata: false,
    });
    await StorageService.instance.init();
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hydownloader-test-');
    await StorageService.instance.saveDownloadDirectory(root.path);
    gates.clear();
    durations.clear();
    runs.clear();
    service = DownloadService.forTesting(
      resolveUrl: (song, quality) async => {
        'url': song.id,
        'size': 1,
        'type': 'flac',
      },
      transfer: (url, path, token) async {
        runs[url] = (runs[url] ?? 0) + 1;
        final gate = gates[url];
        if (gate != null) {
          await Future.any([
            gate.future,
            token.whenCancel.then<void>((error) => throw error),
          ]);
        }
        if (token.isCancelled) throw token.cancelError!;
        await File(path).writeAsString(url);
      },
      readDuration: (path) async {
        final id = await File(path).readAsString();
        return durations.containsKey(id) ? durations[id] : 180000;
      },
    );
  });

  tearDown(() async {
    service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await root.delete(recursive: true);
  });

  test('时长检测只拦截 VIP 试听，不误判短曲或未知时长', () {
    for (final duration in [20000, 30000, 30900]) {
      expect(
        AudioDurationService.isVipPreview(
          isVip: true,
          expectedMs: 180000,
          actualMs: duration,
        ),
        isTrue,
      );
    }
    expect(
      AudioDurationService.isVipPreview(
        isVip: false,
        expectedMs: 180000,
        actualMs: 30000,
      ),
      isFalse,
    );
    expect(
      AudioDurationService.isVipPreview(
        isVip: true,
        expectedMs: 30000,
        actualMs: 30000,
      ),
      isFalse,
    );
    expect(
      AudioDurationService.isVipPreview(
        isVip: true,
        expectedMs: 180000,
        actualMs: null,
      ),
      isFalse,
    );
    expect(AudioDurationService.isFullLength(180000, 60000), isFalse);
    expect(AudioDurationService.isFullLength(180000, 179000), isTrue);
  });

  test('暂停当前和新增 VIP，普通歌曲继续，手动继续只放行单曲', () async {
    gates['cause'] = Completer<void>();
    gates['vip'] = Completer<void>();
    durations['cause'] = 30000;
    final cause = await service.enqueueSong(song('cause'));
    final vip = await service.enqueueSong(song('vip'));
    final free = await service.enqueueSong(song('free', vip: false));
    await until(() => runs['vip'] == 1);
    gates['cause']!.complete();
    await until(
      () =>
          cause.status == DownloadStatus.completed &&
          free.status == DownloadStatus.completed,
    );
    expect(cause.isPreview, isTrue);
    expect(cause.fileName, endsWith('.flac'));
    expect(await File(cause.fullFilePath).exists(), isTrue);
    expect(vip.status, DownloadStatus.paused);
    expect(vip.pausedForVip, isTrue);
    final added = await service.enqueueSong(song('added'));
    expect(added.status, DownloadStatus.paused);
    service.resumeAll();
    await service.enqueueSong(song('vip'));
    expect(vip.status, DownloadStatus.paused);
    service.resumeTask(vip);
    await until(() => runs['vip'] == 2);
    gates['vip']!.complete();
    await until(() => vip.status == DownloadStatus.completed);
    expect(vip.ignoreVipRestriction, isTrue);
    expect(added.status, DownloadStatus.paused);
    expect(service.vipBlockedBy, same(cause));
  });

  test('重试仍为试听不解除保护，恢复完整时长仅继续保护暂停的任务', () async {
    durations['cause'] = 20000;
    final cause = await service.enqueueSong(song('cause'));
    await until(
      () => cause.status == DownloadStatus.completed && !service.isRetryingVip,
    );
    final vip = await service.enqueueSong(song('vip'));
    final manualPause = await service.enqueueSong(song('manual'));
    service.pauseTask(manualPause);
    service.retryVipSong();
    await until(() => !service.isRetryingVip && runs['cause'] == 2);
    expect(service.vipBlockedBy, same(cause));
    expect(vip.status, DownloadStatus.paused);
    durations['cause'] = 180000;
    service.retryVipSong();
    await until(
      () =>
          service.vipBlockedBy == null &&
          vip.status == DownloadStatus.completed,
    );
    expect(cause.isPreview, isFalse);
    expect(manualPause.status, DownloadStatus.paused);
  });

  test('重试失败保留保护及原文件，取消触发项后依旧可重试', () async {
    durations['cause'] = 30000;
    final cause = await service.enqueueSong(song('cause'));
    await until(
      () => cause.status == DownloadStatus.completed && !service.isRetryingVip,
    );
    service.cancelTask(cause);
    final originalBytes = await File(cause.fullFilePath).readAsBytes();
    durations['cause'] = 60000;
    service.retryVipSong();
    await until(
      () => cause.status == DownloadStatus.failed && !service.isRetryingVip,
    );
    expect(service.vipBlockedBy, same(cause));
    expect(service.tasks, contains(cause));
    expect(await File(cause.fullFilePath).readAsBytes(), originalBytes);
    durations['cause'] = null;
    service.retryVipSong();
    await until(
      () => cause.status == DownloadStatus.failed && !service.isRetryingVip,
    );
    expect(service.vipBlockedBy, same(cause));

    durations['cause'] = 180000;
    service.retryVipSong();
    await until(() => service.vipBlockedBy == null);
  });

  test('快速暂停继续不会由旧运行覆盖新状态', () async {
    gates['vip'] = Completer<void>();
    final vip = await service.enqueueSong(song('vip'));
    await until(() => runs['vip'] == 1);
    service.pauseTask(vip);
    service.resumeTask(vip);
    await until(() => runs['vip'] == 2);
    gates['vip']!.complete();
    await until(() => vip.status == DownloadStatus.completed);
    expect(service.vipBlockedBy, isNull);
  });

  test('授权文件名包含空格、中文和斜线时保留 URI 边界', () {
    const root = 'saf:dHJlZQ==/音乐';
    final path = FileAccess.join(root, '歌手 / 歌曲.flac');
    expect(FileAccess.fileName(path), '歌手 / 歌曲.flac');
    expect(
      FileAccess.fileName(FileAccess.withExtension(path, '.lrc')),
      '歌手 / 歌曲.lrc',
    );
  });
}
