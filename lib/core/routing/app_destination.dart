import 'package:flutter/material.dart';

/// Platform-independent destinations. More inbox sections arrive with storage.
enum AppDestination {
  dashboard('Overview', Icons.space_dashboard_outlined),
  analyze('Analyze post', Icons.add_box_outlined);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}
