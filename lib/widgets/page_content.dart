import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.desktopBreakpoint;
    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? AppSpacing.page : 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}
