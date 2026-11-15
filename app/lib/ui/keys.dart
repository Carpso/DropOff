import 'package:flutter/material.dart';

/// Shared keys bound to the root MaterialApp so feature code never has to
/// import main.dart (which would be a circular import).

/// Root scaffoldMessenger — every toast renders in the root overlay, above
/// modal sheets, dialogs and route transitions.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
