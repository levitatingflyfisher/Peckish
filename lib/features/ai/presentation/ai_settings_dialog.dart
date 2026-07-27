import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// Configure (or turn off) the guesstimate brain. Saving a key or an
/// endpoint IS the opt-in; Off deletes the stored key. The copy is the
/// privacy contract: only the words you type in the guess box ever leave,
/// and only to the service configured here.
Future<void> showAiSettingsDialog(BuildContext context, WidgetRef ref) async {
  final current = await ref.read(aiConfigProvider.future);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _AiSettingsDialog(current: current),
  );
}

class _AiSettingsDialog extends ConsumerStatefulWidget {
  const _AiSettingsDialog({required this.current});

  final AiConfig current;

  @override
  ConsumerState<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends ConsumerState<_AiSettingsDialog> {
  late AiBackend _backend = widget.current.backend;
  late final _key = TextEditingController(text: widget.current.anthropicKey);
  late final _url = TextEditingController(text: widget.current.baseUrl);
  late final _model = TextEditingController(text: widget.current.model);

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('AI guesstimate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When you use the guess box, the words you typed there — and '
              'nothing else — go to the service you pick here. Off means '
              'nothing ever leaves.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<AiBackend>(
              groupValue: _backend,
              onChanged: (v) => setState(() => _backend = v!),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<AiBackend>(
                    value: AiBackend.none,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Off'),
                  ),
                  const RadioListTile<AiBackend>(
                    value: AiBackend.openaiCompat,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Local server'),
                    subtitle: Text('llamafile, Ollama, LM Studio…'),
                  ),
                  if (_backend == AiBackend.openaiCompat) ...[
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'http://localhost:11434/v1',
                      ),
                    ),
                    TextField(
                      controller: _model,
                      decoration: const InputDecoration(
                        labelText: 'Model name',
                        hintText: 'qwen2.5:1.5b',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const RadioListTile<AiBackend>(
                    value: AiBackend.anthropic,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Claude (your own key)'),
                    subtitle: Text('Stored on this device only'),
                  ),
                  if (_backend == AiBackend.anthropic)
                    TextField(
                      controller: _key,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API key',
                        hintText: 'sk-ant-…',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await ref.read(aiConfigRepositoryProvider).save(AiConfig(
          backend: _backend,
          anthropicKey: _key.text.trim(),
          baseUrl: _url.text.trim(),
          model: _model.text.trim(),
        ));
    ref.invalidate(aiConfigProvider);
    if (mounted) Navigator.of(context).pop();
  }
}
