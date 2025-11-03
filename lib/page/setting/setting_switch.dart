import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';

class SettingSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double titleFontSize;
  final double subtitleFontSize;
  final int subtitleAlpha;

  const SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.titleFontSize = 16,
    this.subtitleFontSize = 13,
    this.subtitleAlpha = 60,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        title: Text(
          title,
          style: TextStyle(fontSize: titleFontSize, color: Theme.of(context).colorScheme.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: subtitleFontSize, color: Theme.of(context).colorScheme.onSurface.withAlpha(subtitleAlpha)),
        ),
        trailing: SizedBox(
          width: 48.0,
          child: FlutterSwitch(
            value: value,
            onToggle: onChanged,
            width: 32.0,
            height: 18.0,
            toggleSize: 14.0,
            borderRadius: 10.0,
            padding: 1.5,
            activeColor: Theme.of(context).colorScheme.primary,
            inactiveColor: Theme.of(context).colorScheme.outline.withAlpha(76),
            toggleColor: Colors.white,
          ),
        ),
        onTap: () => onChanged(!value),
    );
  }
}
