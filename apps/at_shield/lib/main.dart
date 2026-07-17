import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'engine/shield_cubit.dart';
import 'ui/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtShieldApp());
}

class AtShieldApp extends StatelessWidget {
  const AtShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ShieldCubit()..boot(),
      child: MaterialApp(
        title: 'A.T. Shield',
        debugShowCheckedModeBanner: false,
        theme: AtShieldTheme.dark(),
        home: const HomeShell(),
      ),
    );
  }
}
