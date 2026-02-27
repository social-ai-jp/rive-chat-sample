import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/rive_luau.dart';
import 'package:rive/rive.dart';
import 'screens/conversation_screen.dart';
import 'ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the rive_native renderer (required before loading any .riv file)
  await RiveNative.init();

  // Initialize the Lua scripting runtime so that Lua scripts embedded in the
  // .riv file (eye tracking, idle sway) execute at runtime.
  // Only available on native platforms (iOS/Android/macOS/Windows/Linux).
  // rive_native 0.1.3 does NOT support LuauState on web (WASM is not wired up).
  if (!kIsWeb) {
    LuauState.init(Factory.rive);
  }

  runApp(const VTuberChatApp());
}

class VTuberChatApp extends StatelessWidget {
  const VTuberChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTuber Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const ConversationScreen(),
    );
  }
}
