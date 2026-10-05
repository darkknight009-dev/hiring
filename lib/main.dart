import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'services/radar/radar_capture.dart';
import 'services/share/share_intake.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final deps = AppDependencies(prefs: prefs);
  final launchShare = await ShareIntake.init();
  if (launchShare != null) {
    await deps.setPendingCapture(launchShare);
  }

  ShareIntake.stream.listen((post) {
    deps.setPendingCapture(post);
  });

  RadarCapture(deps).start();

  runApp(
    AppDependenciesScope(
      deps: deps,
      child: HiringRadarApp(deps: deps),
    ),
  );
}
