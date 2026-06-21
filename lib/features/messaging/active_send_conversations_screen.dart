import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../providers/active_send_provider.dart';
import '../../providers/messaging_provider.dart';
import 'conversation_detail_screen.dart';

class ActiveSendConversationsScreen extends StatefulWidget {
  final int campaignId;
  final int? sessionId;
  const ActiveSendConversationsScreen({super.key, required this.campaignId, this.sessionId});

  @override
  State<ActiveSendConversationsScreen> createState() => _ActiveSendConversationsScreenState();
}

class _ActiveSendConversationsScreenState extends State<ActiveSendConversationsScreen> {
  String _filter = 'all'; // all, replied
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  bool _readMarked = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ActiveSendProvider(widget.campaignId, messaging: context.read<MessagingProvider>()),
      builder: (context, child) {
        final provider = Provider.of<ActiveSendProvider>(context);

        // Mark session as read once when the provider is ready
        if (!_readMarked && widget.sessionId != null) {
          _readMarked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.markSessionRead(widget.sessionId!);
          });
        }

        // Apply search filter
        var displayList = provider.conversations;
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          displayList = displayList.where((c) =>
            c.phoneNumber.toLowerCase().contains(q) ||
            (c.lastMessage?.toLowerCase().contains(q) ?? false)
          ).toList();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Conversations'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list_rounded),
                tooltip: 'Filter',
                onSelected: (v) {
                  setState(() => _filter = v);
                  provider.loadConversations(
                    replied: v == 'replied' ? true : null,
                  );
                },
                itemBuilder: (_) => [
                  _buildFilterItem('all', 'All'),
                  _buildFilterItem('replied', 'Replied'),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // Multiple progress cards — one per session
              if (provider.sessions.isNotEmpty)
                ...provider.sessions.map((sess) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _SessionProgressCard(
                    session: sess,
                    onTogglePause: sess.completed || sess.stopped ? null : () => provider.togglePause(sess.sessionId),
                    onStop: (sess.completed || sess.stopped) ? null : () async {
                      final ok = await ConfirmDialog.show(
                        context,
                        title: 'Stop sending?',
                        message: 'This will stop this send session.',
                        confirmLabel: 'Stop',
                        confirmColor: AppColors.error,
                      );
                      if (ok && context.mounted) {
                        await provider.stopSessionById(sess.sessionId);
                      }
                    },
                    onRemove: (sess.completed || sess.stopped) ? () async {
                      final ok = await ConfirmDialog.show(
                        context,
                        title: 'Remove session?',
                        message: 'This will remove the session from the list. Conversations are preserved.',
                        confirmLabel: 'Remove',
                        confirmColor: AppColors.error,
                      );
                      if (ok && context.mounted) {
                        await provider.removeSessionById(sess.sessionId);
                      }
                    } : null,
                  ),
                )),
              if (provider.sessions.isNotEmpty) const SizedBox(height: 4),
              const Divider(height: 1),
              // Conversations list
              Expanded(
                child: provider.loading
                    ? const Center(child: CircularProgressIndicator())
                    : displayList.isEmpty
                        ? const EmptyState(
                            icon: Icons.forum_outlined,
                            title: 'No conversations yet',
                            subtitle: 'Conversations will appear here as messages are sent.',
                          )
                        : RefreshIndicator(
                            onRefresh: () => provider.loadConversations(
                              replied: _filter == 'replied' ? true : null,
                            ),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: displayList.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 2),
                              itemBuilder: (context, i) {
                                final c = displayList[i];
                                final sendStatus = provider.conversationSendStatus[c.id];
                                return _ActiveConversationTile(
                                  conversation: c,
                                  sendStatus: sendStatus,
                                  onTap: () async {
                                    await provider.loadMessages(c.id!);
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ConversationDetailScreen(
                                          conversation: c,
                                          simSlot: provider.sessions.isNotEmpty
                                              ? provider.sessions.first.simSlot
                                              : 'SIM 1',
                                          showControls: false,
                                        ),
                                      ),
                                    );
                                    provider.reloadConversations();
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _buildFilterItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_filter == value) ...[
            const Icon(Icons.check, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    );
  }
}

/// Per-session progress card
class _SessionProgressCard extends StatelessWidget {
  final SessionProgress session;
  final VoidCallback? onTogglePause;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;

  const _SessionProgressCard({
    required this.session,
    this.onTogglePause,
    this.onStop,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final progress = session.total > 0 ? session.dispatched / session.total : 0.0;
    final remaining = (session.total - session.dispatched).clamp(0, 1 << 60);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (session.stopped)
                const StatusBadge(label: 'STOPPED', color: AppColors.error)
              else if (session.completed)
                const StatusBadge(label: 'COMPLETED', color: AppColors.success)
              else if (session.paused)
                const StatusBadge(label: 'PAUSED', color: Colors.orange)
              else if (session.resting)
                Row(
                  children: [
                    const StatusBadge(label: 'RESTING', color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      '${session.restRemaining}s',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                )
              else if (session.nextSendCountdown > 0)
                Row(
                  children: [
                    const StatusBadge(label: 'SENDING', color: AppColors.primary),
                    const SizedBox(width: 8),
                    Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${session.nextSendCountdown}s',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                )
              else
                const StatusBadge(label: 'SENDING', color: AppColors.primary),
              Row(
                children: [
                  Text('SIM: ${session.simSlot}',
                    style: Theme.of(context).textTheme.bodySmall),
                  if (session.running) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: session.paused ? 'Resume' : 'Pause',
                      icon: Icon(
                        session.paused
                            ? Icons.play_circle_rounded
                            : Icons.pause_circle_rounded,
                        color: session.paused ? AppColors.success : AppColors.darkSubtext,
                        size: 20,
                      ),
                      onPressed: onTogglePause,
                    ),
                    IconButton(
                      tooltip: 'Stop',
                      icon: const Icon(Icons.stop_circle_rounded, color: AppColors.error, size: 20),
                      onPressed: onStop,
                    ),
                  ],
                  if (onRemove != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, color: AppColors.darkSubtext, size: 20),
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (session.monitorNumber != null && session.monitorNumber!.isNotEmpty) ...[
            Text('Monitor: ${session.monitorNumber}',
              style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${session.sent} / ${session.total} sent',
                style: Theme.of(context).textTheme.bodySmall),
              if (session.failed > 0)
                Text('${session.failed} failed',
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text('$remaining remaining',
            style: Theme.of(context).textTheme.bodySmall),
          if (session.completed) ...[
            const SizedBox(height: 8),
            Text(
              'Bulk send completed! ${session.sent} sent, ${session.failed} failed.',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (session.stopped) ...[
            const SizedBox(height: 8),
            Text(
              'Session stopped. ${session.sent} sent, ${session.failed} failed.',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Conversation tile matching the imported conversations style
class _ActiveConversationTile extends StatelessWidget {
  final dynamic conversation;
  final String? sendStatus;
  final VoidCallback onTap;

  const _ActiveConversationTile({
    required this.conversation,
    this.sendStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final phone = conversation.phoneNumber as String? ?? '';
    final lastMsg = conversation.lastMessage as String?;
    final lastDirection = conversation.lastDirection as String?;
    final unread = conversation.unread;
    final lastActivity = conversation.lastActivity as String?;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: unread
            ? BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                border: Border(
                  left: BorderSide(color: AppColors.primary, width: 3),
                ),
              )
            : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: unread
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : AppColors.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.person_rounded,
                size: 22,
                color: unread ? AppColors.primary : AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          phone,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (lastDirection == 'out') ...[
                        const Icon(Icons.reply_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          lastMsg ?? 'No messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status icon - only show for outgoing last message
            if (lastDirection == 'out')
              _StatusIconSmall(status: sendStatus),
            const SizedBox(width: 4),
            if (lastActivity != null)
              Text(
                _formatTime(lastActivity),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.darkSubtext,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }
}

class _StatusIconSmall extends StatelessWidget {
  final String? status;
  const _StatusIconSmall({this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null || status!.isEmpty) return const SizedBox.shrink();
    switch (status) {
      case 'sending':
        return const SizedBox(
          width: 14, height: 14,
          child: Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.amber),
        );
      case 'sent':
        return const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success);
      case 'failed':
        return const Icon(Icons.cancel_rounded, size: 14, color: AppColors.error);
      default:
        return const SizedBox.shrink();
    }
  }
}
