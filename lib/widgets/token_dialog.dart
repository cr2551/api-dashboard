import 'package:flutter/material.dart';

/// Asks for the backend access token. Returns the entered token, or null if
/// the dialog was cancelled. The token is only held in memory by the caller.
Future<String?> showTokenDialog(
  BuildContext context, {
  bool rejected = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TokenDialog(rejected: rejected),
);

class _TokenDialog extends StatefulWidget {
  const _TokenDialog({required this.rejected});

  final bool rejected;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  final _controller = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final token = _controller.text.trim();
    if (token.isNotEmpty) Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backend access token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.rejected
                ? 'The last token was rejected. Enter the API_TOKEN the '
                      'backend was started with.'
                : 'Enter the API_TOKEN the backend was started with. It is '
                      'kept in memory only, so you will be asked again after '
                      'a restart.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Access token',
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show token' : 'Hide token',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
