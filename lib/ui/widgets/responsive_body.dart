import 'package:flutter/material.dart';

/// Constrains scrollable tab and settings content to 760px on tablets/desktop
/// while keeping full-width compact phone layout and SafeArea clearance.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    );
  }
}
