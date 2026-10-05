import 'package:flutter/material.dart';

/// A comma/enter-separated keyword input that renders the parsed values as
/// deletable chips. Used for job roles and locations in onboarding and in
/// Settings; the same values drive the radar's capture filter.
class KeywordField extends StatefulWidget {
  const KeywordField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hint,
    this.suggestions = const [],
  });

  final String label;
  final String? hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// Quick-add chips shown when their keyword is not already selected.
  final List<String> suggestions;

  @override
  State<KeywordField> createState() => _KeywordFieldState();
}

class _KeywordFieldState extends State<KeywordField> {
  final _controller = TextEditingController();

  @override
  void didUpdateWidget(covariant KeywordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the text field in sync when an outside save resets the values.
    if (widget.values.length != oldWidget.values.length) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final added = raw
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .where((entry) => !widget.values.contains(entry))
        .toList();
    if (added.isEmpty && raw.trim().isEmpty) return;
    _controller.clear();
    widget.onChanged([...widget.values, ...added]);
  }

  void _remove(String value) =>
      widget.onChanged(widget.values.where((v) => v != value).toList());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final available = widget.suggestions
        .where((suggestion) => !widget.values.contains(suggestion))
        .toList();

    return Column(
      key: ValueKey('keyword-field-${widget.label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            helperText: 'Type and press enter, or separate with commas.',
            prefixIcon: const Icon(Icons.sell_outlined, size: 20),
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: _commit,
          onChanged: (value) {
            if (value.contains(',')) _commit(value);
          },
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in widget.values)
                InputChip(
                  label: Text(value),
                  onDeleted: () => _remove(value),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
        if (available.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Quick add:',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              for (final suggestion in available)
                ActionChip(
                  label: Text(suggestion),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () => _commit(suggestion),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
