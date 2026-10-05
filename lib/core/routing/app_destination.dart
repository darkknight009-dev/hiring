import 'package:flutter/material.dart';

/// Platform-independent destinations. New sections arrive with features.
enum AppDestination {
  dashboard('Overview', Icons.space_dashboard_outlined),
  opportunities('Opportunities', Icons.inbox_outlined),
  analyze('Analyze post', Icons.add_box_outlined),
  settings('Settings', Icons.settings_outlined);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}
