import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/icons.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/browse_providers.dart';
import '../state/session_providers.dart';

/// AVPlayer 解不了封装的容器（mkv / webm / avi / flv / wmv …）走这一页，用随包带的 libmpv。
///
/// 系统播放器只认 Apple 那几种容器，Matroska 连「打开」这一步都过不去 —— 所以 mkv 不是
/// 拖不动，是根本没有画面。这里交给 mpv：地址仍出自 [AuthProxy]（补 Basic 认证、原样转发
/// Range），mpv 自己发分段请求，因此照样边下边播、抬手就拖；内嵌的 .ass/.ssa 特效字幕
/// 由 libass 直接渲染。流式起不来时退回整段下载再本地播，和 AVPlayer 那条路同一个兜底思路。
class MpvVideoPage extends ConsumerStatefulWidget {
  const MpvVideoPage({required this.entry, this.localFile, super.key});

  final RemoteEntry entry;

  /// 压缩包内条目：已解压到沙盒，直接放本地文件。
  final File? localFile;

  @override
  ConsumerState<MpvVideoPage> createState() => _MpvVideoPageState();
}

class _MpvVideoPageState extends ConsumerState<MpvVideoPage> {
  final _player = Player(configuration: const PlayerConfiguration(title: 'Vault'));
  late final VideoController _video = VideoController(_player);

  final _subs = <StreamSubscription<dynamic>>[];
  bool _loading = true;
  bool _buffering = false;
  String? _error;

  /// 流式失败退回整段下载只做一次，免得错误流反复触发重建。
  bool _fallbackTried = false;

  @override
  void initState() {
    super.initState();
    // mpv 把解封装失败、断流这些都写在 error 流里，而不是让 open() 抛异常，
    // 所以错误处理必须挂在打开动作之外。
    _subs.add(_player.stream.error.listen((message) {
      if (message.isEmpty) return;
      if (!_fallbackTried && widget.localFile == null) {
        unawaited(_downloadAndPlay());
        return;
      }
      if (mounted) setState(() => _error = message);
    }));
    _subs.add(_player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    }));
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    final local = widget.localFile ?? await _cachedFile();
    await _play(local == null ? null : Uri.file(local.path).toString());
    if (local != null) return;
    // 流式优先：代理地址是 http://127.0.0.1:port/…，认证与 Range 都由它带。
    final url = await ref.read(proxyProvider).urlFor(widget.entry.path);
    await _play(url.toString());
  }

  Future<void> _play(String? uri) async {
    if (uri == null) {
      _fail('拿不到播放地址。');
      return;
    }
    try {
      await _player.open(Media(uri), play: true);
      if (!mounted) return;
      setState(() => _loading = false);
    } on Object catch (e) {
      if (widget.localFile == null && !_fallbackTried) {
        await _downloadAndPlay();
        return;
      }
      _fail('$e');
    }
  }

  Future<void> _downloadAndPlay() async {
    if (_fallbackTried) return;
    _fallbackTried = true;
    if (mounted) setState(() => _buffering = true);
    try {
      final file = await ref.read(cachedFileProvider(cacheKeyFor(widget.entry)).future);
      await _play(Uri.file(file.path).toString());
    } on Object catch (e) {
      _fail('$e');
    }
  }

  /// 只查沙盒里已有的完整文件，不触发下载。
  Future<File?> _cachedFile() async {
    try {
      final key = cacheKeyFor(widget.entry);
      final cache = ref.read(cacheProvider);
      final file = await cache.fileFor(
        bucketForExtension(key.ext),
        remotePath: key.path,
        displayName: key.name,
        etag: key.etag,
        ext: key.ext.startsWith('.') ? key.ext.substring(1) : key.ext,
      );
      if (await file.exists() && await file.length() > 0) {
        await cache.touch(file);
        return file;
      }
      return null;
    } on Object {
      return null;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _buffering = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: error != null
                ? _failed(error)
                : Video(
                    controller: _video,
                    // 深色页面下控件用 Mac 那套（有实底背景），免得贴在黑底上看不清。
                    controls: AdaptiveVideoControls,
                  ),
          ),
          if (_loading || _buffering)
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: VaultColors.accent),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: IconBtn(icon: 'back', color: Colors.white, onTap: () => Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }

  Widget _failed(String message) => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VIcon('video', size: 30, color: VaultColors.chevron),
                const SizedBox(height: 14),
                Text(
                  '这个文件解不开：${widget.entry.name}\n$message',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: VaultColors.muted, height: 1.7),
                ),
              ],
            ),
          ),
        ),
      );
}
