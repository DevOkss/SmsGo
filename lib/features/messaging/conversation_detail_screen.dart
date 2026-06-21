import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linkify/linkify.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../database/database.dart';
import '../../models/conversation.dart';
import '../../models/conversation_message.dart';
import '../../providers/messaging_provider.dart';
import '../../repositories/conversation_repository.dart';
import '../../services/sms_gateway.dart';
import '../../services/sms_service.dart';

class ConversationDetailScreen extends StatefulWidget {
  final Conversation conversation;
  final String? simSlot;
  final bool showControls;
  const ConversationDetailScreen({
    super.key,
    required this.conversation,
    this.simSlot,
    this.showControls = true,
  });

  @override
  State<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  final _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late ConversationRepository _repo;
  List<ConversationMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _showJumpButton = false;
  String _selectedSim = 'SIM 1';
  String _sessionSimSlot = 'SIM 1';
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  StreamSubscription<Map<String, dynamic>>? _sendResultSub;

  // Session control state
  int? _sessionId;
  bool _sessionRunning = false;
  bool _sessionPaused = false;

  @override
  void initState() {
    super.initState();
    _selectedSim = widget.simSlot ?? 'SIM 1';
    _sessionId = widget.conversation.sessionId;
    _init();
    _scrollCtrl.addListener(() {
      try {
        if (!_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        final atBottom = _scrollCtrl.position.pixels >= (max - 40);
        if (_showJumpButton == atBottom) {
          setState(() => _showJumpButton = !atBottom);
        }
      } catch (_) {}
    });
  }

  Future<void> _init() async {
    final db = await AppDatabase.instance.database;
    _repo = ConversationRepository(db);

    // Load session state
    if (_sessionId != null) {
      final rows = await db.query(
        'sending_sessions',
        where: 'id = ?',
        whereArgs: [_sessionId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        _sessionSimSlot = rows.first['sim_slot'] as String? ?? 'SIM 1';
        final running = rows.first['running'] as int? ?? 0;
        final isPaused = rows.first['paused'] as int? ?? 0;
        _sessionRunning = running == 1;
        _sessionPaused = isPaused == 1 && running == 1;
        if (widget.simSlot == null) {
          _selectedSim = _sessionSimSlot;
        }
      }
    }

    // Mark conversation as read
    await _repo.markRead(widget.conversation.id!);

    await _loadMessages();

    // Subscribe to real-time incoming messages for this conversation
    _incomingSub = SmsService.instance.incomingEvents.listen((event) {
      final eventConvId = event['conversationId'] as int?;
      if (eventConvId == widget.conversation.id && mounted) {
        _loadMessages();
      }
    });

    // Subscribe to send results for realtime status updates
    _sendResultSub = SmsService.instance.sendEvents.listen((event) {
      if (!mounted) return;
      final phone = normalizePhone((event['phone'] ?? '') as String);
      if (phone == normalizePhone(widget.conversation.phoneNumber)) {
        _loadMessages();
      }
      // Update session state when events arrive
      _refreshSessionState();
    });
  }

  Future<void> _refreshSessionState() async {
    if (_sessionId == null) return;
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'sending_sessions',
        where: 'id = ?',
        whereArgs: [_sessionId],
        limit: 1,
      );
      if (rows.isNotEmpty && mounted) {
        final running = rows.first['running'] as int? ?? 0;
        final isPaused = rows.first['paused'] as int? ?? 0;
        setState(() {
          _sessionRunning = running == 1;
          _sessionPaused = isPaused == 1 && running == 1;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    final msgs = await _repo.getMessagesForConversation(widget.conversation.id!);
    if (!mounted) return;
    final changed = _messages.length != msgs.length;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _sendResultSub?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    try {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      if (_showJumpButton) setState(() => _showJumpButton = false);
    } catch (_) {}
  }

  Widget _statusIcon(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s == 'sending') {
      return const SizedBox(
        width: 14, height: 14,
        child: Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.amber),
      );
    }
    if (s == 'sent') {
      return const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success);
    }
    if (s == 'failed') {
      return const Icon(Icons.cancel_rounded, size: 14, color: AppColors.error);
    }
    return const SizedBox.shrink();
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  bool _canReplyTo(String phone) {
    return isRealPhoneNumber(phone);
  }

  Future<void> _sendReply() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();

    setState(() => _sending = true);

    final sendingId = await _repo.addMessage(
      widget.conversation.id!,
      'out',
      text,
      status: 'sending',
    );

    await _loadMessages();

    try {
      final simIndex = _selectedSim == 'SIM 2' ? 1 : 0;

      await SmsGateway.sendSms(
        to: widget.conversation.phoneNumber,
        message: text,
        simSlot: simIndex,
      );
    } catch (_) {
      await _repo.updateMessageStatus(sendingId, 'failed');
    }

    await _repo.markReplied(widget.conversation.id!, true);
    setState(() => _sending = false);
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversation.phoneNumber,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (!_loading)
              Text('${_messages.length} messages',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (_selectedSim == 'SIM 2' ? Colors.orange : AppColors.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sim_card_rounded, size: 14,
                    color: _selectedSim == 'SIM 2' ? Colors.orange.shade700 : AppColors.primary),
                  const SizedBox(width: 4),
                  Text(_selectedSim.replaceAll('SIM ', 'S'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _selectedSim == 'SIM 2' ? Colors.orange.shade700 : AppColors.primary,
                    )),
                ],
              ),
            ),
            tooltip: 'Select SIM',
            onSelected: (v) => setState(() => _selectedSim = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'SIM 1',
                checked: _selectedSim == 'SIM 1',
                child: const Text('SIM 1'),
              ),
              CheckedPopupMenuItem(
                value: 'SIM 2',
                checked: _selectedSim == 'SIM 2',
                child: const Text('SIM 2'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _showJumpButton
          ? FloatingActionButton.small(
              tooltip: 'Jump to latest',
              onPressed: _scrollToBottom,
              child: const Icon(Icons.arrow_downward),
            )
          : null,
      body: Column(
        children: [
          // Session control bar for active send conversations
          if (widget.showControls && _sessionId != null && _sessionRunning)
            _SessionControlBar(
              paused: _sessionPaused,
              onTogglePause: () async {
                final mp = context.read<MessagingProvider>();
                if (_sessionPaused) {
                  await mp.resumeSending(_sessionId!);
                } else {
                  await mp.pauseSending(_sessionId!);
                }
                await _refreshSessionState();
              },
              onStop: () async {
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Stop sending?',
                  message: 'This will stop the current send session.',
                  confirmLabel: 'Stop',
                  confirmColor: AppColors.error,
                );
                if (ok && mounted) {
                  await context.read<MessagingProvider>().stopSending(_sessionId!);
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet.\nSend a reply to start the conversation.',
                          textAlign: TextAlign.center),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final isOut = m.direction == 'out';
                          return _MessageBubble(
                            message: m.message,
                            isOutgoing: isOut,
                            status: isOut ? m.status : null,
                            time: _formatTime(m.createdAt),
                            statusIcon: isOut ? _statusIcon(m.status) : null,
                            simSlot: m.simSlot,
                            recipientPhone: isOut ? widget.conversation.phoneNumber : null,
                          );
                        },
                      ),
          ),
          SafeArea(
            child: _canReplyTo(widget.conversation.phoneNumber)
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).dividerTheme.color ?? Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            decoration: InputDecoration(
                              hintText: 'Type a reply...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendReply(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: _sending
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded, color: AppColors.primary),
                          onPressed: _sending ? null : _sendReply,
                        ),
                      ],
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).dividerTheme.color ?? Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "This sender can't receive replies. Contact them directly.",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Session control bar shown at top of conversation detail for active send sessions
class _SessionControlBar extends StatelessWidget {
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onStop;

  const _SessionControlBar({
    required this.paused,
    required this.onTogglePause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: paused
            ? Colors.orange.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            paused ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
            size: 18,
            color: paused ? Colors.orange : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              paused ? 'Campaign paused' : 'Campaign sending...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: paused ? Colors.orange.shade700 : AppColors.primary,
              ),
            ),
          ),
          // Toggle pause/resume
          IconButton(
            tooltip: paused ? 'Resume' : 'Pause',
            icon: Icon(
              paused ? Icons.play_circle_rounded : Icons.pause_circle_rounded,
              size: 22,
              color: paused ? AppColors.success : AppColors.darkSubtext,
            ),
            onPressed: onTogglePause,
            visualDensity: VisualDensity.compact,
          ),
          // Stop
          IconButton(
            tooltip: 'Stop',
            icon: const Icon(Icons.stop_circle_rounded, size: 22, color: AppColors.error),
            onPressed: onStop,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isOutgoing;
  final String? status;
  final String time;
  final Widget? statusIcon;
  final String? simSlot;
  final String? recipientPhone;

  const _MessageBubble({
    required this.message,
    required this.isOutgoing,
    this.status,
    required this.time,
    this.statusIcon,
    this.simSlot,
    this.recipientPhone,
  });

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        final uri = Uri.parse('https://$url');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }
  }

  Widget _buildLinkifiedText(BuildContext context) {
    final elements = linkify(message, options: LinkifyOptions(humanize: false));
    final defaultColor = isOutgoing
        ? Colors.white
        : Theme.of(context).textTheme.bodyMedium?.color;
    final linkColor = isOutgoing
        ? Colors.white70
        : Theme.of(context).colorScheme.primary;

    return SelectableText.rich(
      TextSpan(
        children: elements.map((element) {
          if (element is LinkableElement) {
            return TextSpan(
              text: element.text,
              style: TextStyle(
                color: linkColor,
                fontSize: 14,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openLink(element.url),
            );
          }
          return TextSpan(
            text: element.text,
            style: TextStyle(
              color: defaultColor,
              fontSize: 14,
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOutgoing ? AppColors.primary : Theme.of(context).cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                  bottomRight: Radius.circular(isOutgoing ? 4 : 16),
                ),
                border: isOutgoing
                    ? null
                    : Border.all(
                        color: Theme.of(context).dividerTheme.color ?? Theme.of(context).dividerColor,
                        width: 0.5,
                      ),
              ),
              child: _buildLinkifiedText(context),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (simSlot != null && simSlot!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(simSlot!, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w500)),
                  ),
                if (isOutgoing && recipientPhone != null && recipientPhone!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('→ $recipientPhone', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                  ),
                Text(time, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                if (statusIcon != null) ...[
                  const SizedBox(width: 4),
                  statusIcon!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
