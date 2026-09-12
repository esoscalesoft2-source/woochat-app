import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Falls back to assets/env/env.json when no --dart-define was supplied.
  await Env.load();

  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // The SDK renamed this parameter; a legacy anon key is still valid here.
      publishableKey: Env.supabaseAnonKey,
    );
  }

  runApp(WooChatApp(configured: Env.isConfigured));
}
