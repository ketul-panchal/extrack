import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:spent/app/app.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/settings/stores.dart';
import 'package:spent/data/providers.dart';

/// Opens local storage, then starts the app. Nothing here touches the network.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = PostHogConfig('phc_tLiVJNjhkL4WrbJYTpSzuxgWJMRstLcv9n2raxTQSvW8');
  config.host = 'https://us.i.posthog.com';
  config.debug = true;
  config.captureApplicationLifecycleEvents = true;
  config.sessionReplay = false;
  config.sessionReplayConfig.maskAllTexts = false;
  config.sessionReplayConfig.maskAllImages = false;
  config.sessionReplayConfig.throttleDelay = const Duration(milliseconds: 1000);
  await Posthog().setup(config);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final store = await PrefsKeyValueStore.open();
  final db = AppDatabase();

  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      databaseProvider.overrideWithValue(db),
    ],
    // Local database work doesn't benefit from automatic retries.
    retry: (_, _) => null,
  );

  runApp(UncontrolledProviderScope(container: container, child: const SpentApp()));
}
