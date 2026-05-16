import 'package:flutter/material.dart';

/// Shared key so deep screens (e.g. driver home sign-out) can return to role picker
/// without importing [RoleSelectionScreen] (avoids circular imports).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
