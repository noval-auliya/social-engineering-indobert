import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/mock_data.dart';
import '../../widgets/loading_widget.dart';
import 'analysis_result_view.dart';

class WhatsAppAnalysisPage extends ConsumerStatefulWidget {
  const WhatsAppAnalysisPage({super.key});

  @override
  ConsumerState<WhatsAppAnalysisPage> createState() =>
      _WhatsAppAnalysisPageState();
}

class _WhatsAppAnalysisPageState extends ConsumerState<WhatsAppAnalysisPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    ref.read(analysisProvider.notifier).analyze(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Analisis Pesan WhatsApp')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tempel pesan yang ingin diperiksa',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: 'Contoh: Selamat! Anda mendapatkan hadiah...',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in MockData.sampleMessages)
                ActionChip(
                  label: Text(
                    s.length > 28 ? '${s.substring(0, 28)}…' : s,
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.bolt, size: 16),
                  onPressed: () {
                    _controller.text = s;
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.text.trim().isEmpty ? null : _analyze,
                  icon: const Icon(Icons.search),
                  label: const Text('Analisis Pesan'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                onPressed: () {
                  _controller.clear();
                  ref.read(analysisProvider.notifier).reset();
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset',
              ),
            ],
          ),
          const SizedBox(height: 20),
          state.when(
            data: (result) => result == null
                ? const SizedBox.shrink()
                : AnalysisResultView(result: result),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: LoadingWidget(
                  message: 'Menganalisis dengan IndoBERT...\n'
                      'Semua diproses di HP.'),
            ),
            error: (e, _) => _ErrorBox(message: '$e'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text('Gagal menganalisis.\n$message')),
          ],
        ),
      ),
    );
  }
}
