import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ebook_app/src/app.dart';
import 'package:flutter_ebook_app/src/common/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sembast/sembast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );
  await LocalStorage.initialize();
  await DatabaseConfig.init(StoreRef<dynamic, dynamic>.main());
  if (kIsWeb) usePathUrlStrategy();
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
