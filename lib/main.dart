import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/network_info.dart';
import 'data/prefs_repository.dart';
import 'state/session_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // mkv / avi 这类容器系统播放器解不了，得靠随包带的 libmpv；注册一次就够。
  MediaKit.ensureInitialized();
  final prefs = await PrefsRepository.open();
  // 一打开就摸一次局域网，逼 iOS 弹「本地网络」授权框；不 await，不挡启动。
  unawaited(triggerLocalNetworkPrompt());
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const VaultApp(),
    ),
  );
}
