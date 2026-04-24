import 'package:flutter/material.dart';
import 'package:example/custom/settings/settings_store.dart';
import 'package:mnsml/mnsml.dart';

class SettingsExample extends StatelessWidget {
  const SettingsExample(this.store, {Key? key}) : super(key: key);

  final SettingsStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: Observer(
      builder:
          (context) => SwitchListTile(
            value: store.useDarkMode,
            title: const Text('Use dark mode'),
            onChanged: (value) {
              store.setDarkMode(value: value);
            },
          ),
    ),
  );
}
