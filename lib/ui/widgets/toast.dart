import 'package:flutter/material.dart';

void toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      width: null,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    ));
}
