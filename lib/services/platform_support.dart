import 'dart:io';

import 'package:flutter/foundation.dart';

/// mobile_scanner only ships a native implementation for these platforms;
/// everywhere else (Windows, Linux desktop) it has no way to access the
/// camera, so callers should show a friendly message instead of a broken
/// scanner.
bool get barcodeScanningSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// google_mlkit_object_detection only ships Android and iOS native
/// implementations (no web, no desktop), and the `camera` package itself has
/// no Windows or macOS implementation either. Obstacle detection only works
/// on Android and iOS.
bool get obstacleDetectionSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Tactile path guidance reads raw camera frames directly (no Windows/macOS
/// camera implementation) and branches on `Platform.isAndroid`/`isIOS`
/// unconditionally, which throws on web. Android and iOS only.
bool get tactilePathSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
