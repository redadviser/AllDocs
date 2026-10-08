import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../common/app_constants.dart';
import '../../common/assistant_flow.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';
import '../viewer/document_viewer_screen.dart';

/// Opens the assistant once the plan and the user's consent allow it.
Future<void> openAssistant(
  BuildContext context,
  DocumentsService documentsService,
) async {
  if (!await ensureAssistantAllowed(context) || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AssistantScreen(documentsService: documentsService),
    ),
  );
}

class _Exchange {
  _Exchange(this.question);

  final String question;
  String? answer;
  List<DocumentFile> sources = const [];
  bool failed = false;
}

/// Questions about the user's documents, answered from the few that match.
/// The conversation lives only on this screen.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.documentsService});

  final DocumentsService documentsService;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _exchanges = <_Exchange>[];
  bool _busy = false;
  ({int used, int limit})? _usage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await AssistantService.usage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {}
  }

  Future<void> _send([String? preset]) async {
    final question = (preset ?? _input.text).trim();
    if (question.isEmpty || _busy) return;
    final exchange = _Exchange(question);
    setState(() {
      _busy = true;
      _exchanges.add(exchange);
      _input.clear();
    });
    _scrollToEnd();

    final language = context.locale.languageCode;
    try {
      final snapshot = await widget.documentsService.loadSnapshot();
      // Hidden documents stay out: they're only reachable behind their PIN.
      final library = [...snapshot.documents, ...snapshot.archivedDocuments];
      final candidates = AssistantService.relevantDocuments(library, question);
      if (candidates.isEmpty) {
        // Nothing matches on the phone: say so without spending a request.
        exchange.answer = AppConstants.assistantNoDocuments.tr();
      } else {
        final result = await AssistantService.ask(
          question,
          candidates,
          language: language,
        );
        exchange.answer = result.answer;
        exchange.sources = [
          for (final id in result.sourceIds)
            ?candidates.where((d) => d.id == id).firstOrNull,
        ];
        _loadUsage();
      }
    } on AssistantException catch (error) {
      exchange
        ..answer = assistantProblemMessage(error.problem)
        ..failed = true;
    } catch (_) {
      exchange
        ..answer = AppConstants.assistantUnavailable.tr()
        ..failed = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  const BackButton(),
                  Icon(Icons.auto_awesome_rounded, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppConstants.assistantTitle.tr(),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_usage case final usage?)
                    Text(
                      AppConstants.assistantUsage.tr(
                        namedArgs: {
                          'used': '${usage.used}',
                          'limit': '${usage.limit}',
                        },
                      ),
                      style: const TextStyle(
                        color: AppTheme.dimText,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _exchanges.isEmpty
                  ? _Welcome(onAsk: _send)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _exchanges.length,
                      itemBuilder: (context, index) => _ExchangeView(
                        exchange: _exchanges[index],
                        onOpen: (document) => openDocumentViewer(
                          context,
                          widget.documentsService,
                          document,
                        ),
                      ),
                    ),
            ),
            _Composer(controller: _input, busy: _busy, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      AppConstants.assistantSuggestion1.tr(),
      AppConstants.assistantSuggestion2.tr(),
      AppConstants.assistantSuggestion3.tr(),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.accent,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppConstants.assistantSubtitle.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onAsk(suggestion),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          suggestion,
                          style: const TextStyle(color: AppTheme.text),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_outward_rounded,
                        size: 18,
                        color: AppTheme.dimText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExchangeView extends StatelessWidget {
  const _ExchangeView({required this.exchange, required this.onOpen});

  final _Exchange exchange;
  final ValueChanged<DocumentFile> onOpen;

  @override
  Widget build(BuildContext context) {
    final answer = exchange.answer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  exchange.question,
                  style: const TextStyle(color: AppTheme.text),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (answer == null)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  AppConstants.assistantThinking.tr(),
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Icon(
                    exchange.failed
                        ? Icons.error_outline_rounded
                        : Icons.auto_awesome_rounded,
                    size: 18,
                    color: exchange.failed ? AppTheme.warning : AppTheme.accent,
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    answer,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            if (exchange.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final document in exchange.sources)
                      ActionChip(
                        avatar: const Icon(
                          Icons.description_outlined,
                          size: 16,
                        ),
                        label: Text(
                          document.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => onOpen(document),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: AppConstants.assistantHint.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
