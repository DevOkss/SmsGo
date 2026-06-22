import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../models/campaign.dart';
import '../../models/monitor_number.dart';
import '../../providers/messaging_provider.dart';
import '../../providers/campaign_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/license_provider.dart';
import '../../services/license_service.dart';
import '../../repositories/lead_repository.dart';
import '../../repositories/conversation_repository.dart';
import '../../database/database.dart';
import '../../services/sms_gateway.dart';

import 'active_send_conversations_screen.dart';
import 'conversations_screen.dart';


class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagingProvider>().loadActiveSessions();
      context.read<CampaignProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messaging'),
        actions: [
          Consumer<MessagingProvider>(
            builder: (context, provider, _) {
              final unread = provider.importedUnreadCount;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Imported Messages',
                    icon: const Icon(Icons.message_rounded),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConversationsScreen()),
                      );
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer2<MessagingProvider, CampaignProvider>(
        builder: (context, msgProvider, campProvider, _) {
          final activeSessions = msgProvider.active;
          final campaigns = campProvider.campaigns.where((c) => !c.archived && c.totalLeads > 0).toList();

          // Group active sessions by campaignId
          final sessionsByCampaign = <int, List<ActiveSend>>{};
          for (final s in activeSessions) {
            sessionsByCampaign.putIfAbsent(s.campaignId, () => []).add(s);
          }

          // Determine available SIMs (not in use by active running sessions)
          final activeSims = msgProvider.getActiveSims();
          final sim1Available = !activeSims.contains('SIM 1');
          final sim2Available = !activeSims.contains('SIM 2');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Available SIMs section
              Text('Available SIM', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (sim1Available)
                    Chip(
                      avatar: const Icon(Icons.sim_card_rounded, size: 16, color: AppColors.success),
                      label: const Text('SIM 1'),
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                    ),
                  if (sim2Available)
                    Chip(
                      avatar: const Icon(Icons.sim_card_rounded, size: 16, color: AppColors.success),
                      label: const Text('SIM 2'),
                      backgroundColor: AppColors.success.withValues(alpha: 0.1),
                    ),
                  if (!sim1Available && !sim2Available)
                    Text('No SIMs available — all in use',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.darkSubtext)),
                  if (sim1Available || sim2Available)
                    Text('${sim1Available && sim2Available ? '2' : '1'} available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.darkSubtext)),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Campaign cards section
              Text('Campaigns', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (campaigns.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No campaigns ready',
                    subtitle: 'Create a campaign and import leads first.',
                  ),
                )
              else
                ...campaigns.map((campaign) {
                  final campaignSessions = sessionsByCampaign[campaign.id!] ?? [];
                  final campaignUnread = campaignSessions.fold<int>(0, (sum, s) => sum + s.unreadCount);

                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Campaign header with icons
                          Row(
                            children: [
                              Expanded(
                                child: Text(campaign.name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              // Conversation icon with badge
                              IconButton(
                                tooltip: 'Conversations',
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(Icons.forum_rounded),
                                    if (campaignUnread > 0)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: AppColors.error,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                          child: Text(
                                            campaignUnread > 99 ? '99+' : '$campaignUnread',
                                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => ActiveSendConversationsScreen(campaignId: campaign.id!),
                                  ));
                                },
                              ),
                              // Start New icon
                              IconButton(
                                tooltip: 'Start New Session',
                                icon: Icon(Icons.play_circle_outline_rounded, color: Theme.of(context).colorScheme.primary),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => SendSetupScreen(
                                      campaign: campaign,
                                      onStarted: () {
                                        context.read<MessagingProvider>().loadActiveSessions();
                                      },
                                    ),
                                  ));
                                },
                              ),
                            ],
                          ),
                          // Session cards under this campaign
                          if (campaignSessions.isNotEmpty) ...[
                            const Divider(height: 16),
                            ...campaignSessions.map((session) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SessionCard(session: session),
                            )),
                          ] else ...[
                            const Divider(height: 16),
                            Text(
                              '${campaign.totalLeads - campaign.sentCount} pending · ${campaign.totalLeads} total',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.darkSubtext),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ActiveSend session;
  const _SessionCard({required this.session});

  Color _badgeColor() {
    if (session.stopped) return AppColors.darkSubtext;
    if (session.completed) return AppColors.success;
    if (session.resting) return Colors.orange;
    if (session.running) return AppColors.success;
    return Colors.orange;
  }

  String _badgeLabel() {
    if (session.completed) return 'COMPLETED';
    if (session.stopped) return 'STOPPED';
    if (session.resting) return 'RESTING';
    if (session.running) return 'RUNNING';
    return 'PAUSED';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? primary.withValues(alpha: 0.06)
            : primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Bulk Sending',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              StatusBadge(label: _badgeLabel(), color: _badgeColor()),
              Text('${session.simSlot} · ${session.targetNetwork}',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (!session.completed && !session.stopped) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.stop_circle_rounded, color: AppColors.error, size: 20),
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: 'Stop sending?',
                      message: 'This will stop this send session.',
                      confirmLabel: 'Stop',
                      confirmColor: AppColors.error,
                    );
                    if (ok && context.mounted) {
                      await context.read<MessagingProvider>().stopSending(session.sessionId);
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: session.running ? 'Pause' : 'Resume',
                  icon: Icon(
                    session.running ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                    color: session.running ? AppColors.darkSubtext : AppColors.success,
                    size: 20,
                  ),
                  onPressed: () async {
                    if (session.running) {
                      await context.read<MessagingProvider>().pauseSending(session.sessionId);
                    } else {
                      await context.read<MessagingProvider>().resumeSending(session.sessionId);
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, color: AppColors.darkSubtext, size: 20),
                onPressed: () async {
                  final ok = await ConfirmDialog.show(
                    context,
                    title: 'Remove session?',
                    message: 'This will remove the session from the list. Conversations are preserved.',
                    confirmLabel: 'Remove',
                    confirmColor: AppColors.error,
                  );
                  if (ok && context.mounted) {
                    await context.read<MessagingProvider>().removeSession(session.sessionId);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (session.monitorNumber != null && session.monitorNumber!.isNotEmpty) ...[
            Text('Monitor: ${session.monitorNumber}',
              style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          ProgressRow(sent: session.sent, total: session.total, failed: session.failed, dispatched: session.dispatched),
          const SizedBox(height: 4),
          Text('${(session.total - session.dispatched).clamp(0, 1 << 60)} remaining',
            style: Theme.of(context).textTheme.bodySmall),
          if (session.isCountingDown && session.countdownSeconds > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: session.resting ? Colors.orange.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    session.resting ? Icons.pause_circle_rounded : Icons.timer_outlined,
                    size: 16,
                    color: session.resting ? Colors.orange : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    session.resting
                        ? 'Resting... ${session.countdownSeconds}s'
                        : 'Next send in ${session.countdownSeconds}s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: session.resting ? Colors.orange : AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (session.lastMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              session.lastMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.darkSubtext,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Send Setup Screen ───────────────────────────────────────────────────────

class SendSetupScreen extends StatefulWidget {
  final Campaign campaign;
  final VoidCallback onStarted;

  const SendSetupScreen({super.key, required this.campaign, required this.onStarted});

  @override
  State<SendSetupScreen> createState() => _SendSetupScreenState();
}

class _SendSetupScreenState extends State<SendSetupScreen> {
  String _simSlot = AppConstants.simSlot1;
  String _targetNetwork = AppConstants.networkAll;
  String _messageMode = AppConstants.categoryRotational;
  int _sendIntervalMin = 3;
  int _sendIntervalMax = 8;
  bool _restEnabled = false;
  int _restSeconds = 30;
  int _restAfterCount = 0;
  int _progressNotifyAfter = 15;
  String? _monitorNumber;
  Map<String, int> _networkCounts = {};
  int _rangeStart = 1;
  int _rangeEnd = 0; // 0 means "all" (will be set to total on load)
  int _totalUnsent = 0;

  final Set<String> _selectedGroups = {};
  bool _testSent = false;
  final _monitorCtrl = TextEditingController();
  final _intervalMinCtrl = TextEditingController(text: '3');
  final _intervalMaxCtrl = TextEditingController(text: '8');
  final _restAfterCtrl = TextEditingController(text: '0');
  final _restDurationCtrl = TextEditingController(text: '30');
  final _progressNotifyCtrl = TextEditingController(text: '15');
  final _rangeStartCtrl = TextEditingController(text: '1');
  final _rangeEndCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotesProvider>().load();
      context.read<MessagingProvider>().loadMonitorNumbers();
      _loadNetworkCounts();
      _loadUnsentCount();
    });
  }

  @override
  void dispose() {
    _monitorCtrl.dispose();
    _intervalMinCtrl.dispose();
    _intervalMaxCtrl.dispose();
    _restAfterCtrl.dispose();
    _restDurationCtrl.dispose();
    _rangeStartCtrl.dispose();
    _rangeEndCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-switch SIM if current selection is disabled by another active session
    final activeSims = context.read<MessagingProvider>().getActiveSims();
    final sim1Disabled = activeSims.contains('SIM 1');
    final sim2Disabled = activeSims.contains('SIM 2');

    String newSlot = _simSlot;
    if (_simSlot == 'SIM 1' && sim1Disabled && !sim2Disabled) {
      newSlot = 'SIM 2';
    } else if (_simSlot == 'SIM 2' && sim2Disabled && !sim1Disabled) {
      newSlot = 'SIM 1';
    }
    if (newSlot != _simSlot) {
      setState(() => _simSlot = newSlot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSims = context.watch<MessagingProvider>().getActiveSims();
    final sim1Disabled = activeSims.contains('SIM 1');
    final sim2Disabled = activeSims.contains('SIM 2');

    return Scaffold(
      appBar: AppBar(title: Text(widget.campaign.name)),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _testSend,
              icon: const Icon(Icons.send_outlined),
              label: Text(_testSent ? 'Re-test Send' : 'Test Send'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _canStartSending ? _startSending : null,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_getSendButtonLabel()),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // SIM Slot
          _SettingSection(
            title: 'SIM Card',
            child: _SimSelector(
              selected: _simSlot,
              sim1Disabled: sim1Disabled,
              sim2Disabled: sim2Disabled,
              onSelected: (v) => setState(() => _simSlot = v),
            ),
          ),

          // Target Network
          _SettingSection(
            title: 'Target Network',
            child: _NetworkTargetChips(
              counts: _networkCounts,
              selected: _targetNetwork,
              onSelected: (v) {
                setState(() => _targetNetwork = v);
                _loadUnsentCount();
              },
            ),
          ),

          // Range Selection
          _SettingSection(
            title: 'Target Range ($_totalUnsent contacts available)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rangeStartCtrl,
                        decoration: InputDecoration(
                          labelText: 'Start',
                          hintText: '1',
                          errorText: _rangeStart < 1 ? 'Must be ≥ 1' : (_rangeStart > _rangeEnd ? 'Must be ≤ End' : null),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) {
                          final val = int.tryParse(v);
                          if (val != null) {
                            setState(() => _rangeStart = val);
                          } else if (v.isEmpty) {
                            setState(() => _rangeStart = 0);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _rangeEndCtrl,
                        decoration: InputDecoration(
                          labelText: 'End',
                          hintText: _totalUnsent.toString(),
                          errorText: _rangeEnd < 1
                              ? 'Must be ≥ 1'
                              : (_rangeEnd > _totalUnsent
                                  ? 'Max is $_totalUnsent'
                                  : (_rangeStart > _rangeEnd ? 'Must be ≥ Start' : null)),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (v) {
                          final val = int.tryParse(v);
                          if (val != null) {
                            setState(() => _rangeEnd = val);
                          } else if (v.isEmpty) {
                            setState(() => _rangeEnd = 0);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (_totalUnsent == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No available targets for the selected network', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Message Mode
          _SettingSection(
            title: 'Message Mode',
            child: AppChipGroup(
              options: [AppConstants.categoryRotational, AppConstants.categorySequential],
              selected: _messageMode,
              onSelected: (v) => setState(() => _messageMode = v),
            ),
          ),

          // Message Groups
          _SettingSection(
            title: 'Message Groups (Spiels)',
            child: Consumer<NotesProvider>(
              builder: (context, notes, _) {
                final groups = notes.groups;
                if (groups.isEmpty) {
                  return Text(
                    'No groups yet. Create groups in the Notes tab.',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                }
                return Column(
                  children: groups.map((g) {
                    final name = g['group_name'] as String;
                    final count = g['note_count'] as int;
                    final selected = _selectedGroups.contains(name);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(name),
                      secondary: Text('$count notes',
                        style: Theme.of(context).textTheme.bodySmall),
                      value: selected,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedGroups.add(name);
                          } else {
                            _selectedGroups.remove(name);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),

          // Send Interval
          _SettingSection(
            title: 'Send Interval (seconds)',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _intervalMinCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      hintText: '3',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 1;
                      setState(() => _sendIntervalMin = val.clamp(1, 300));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _intervalMaxCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max',
                      hintText: '8',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 1;
                      setState(() => _sendIntervalMax = val.clamp(1, 300));
                    },
                  ),
                ),
              ],
            ),
          ),

          // Rest Mode
          _SettingSection(
            title: 'Rest Mode',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable rest intervals'),
                  subtitle: Text(_restEnabled
                      ? 'Adds $_restSeconds seconds after each send'
                      : 'Fixed pause after each send'),
                  value: _restEnabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() {
                    _restEnabled = v;
                    if (!v) {
                      _restAfterCount = 0;
                      _restAfterCtrl.clear();
                    }
                  }),
                ),
                if (_restEnabled) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _restDurationCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rest duration (seconds)',
                      hintText: '30',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 30;
                      setState(() => _restSeconds = val.clamp(5, 600));
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restAfterCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rest after N messages (0 = disabled)',
                      hintText: 'e.g. 50',
                      helperText: 'After sending this many messages, rest for the duration above',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 0;
                      setState(() => _restAfterCount = val);
                    },
                  ),
                ],
              ],
            ),
          ),

          // Monitor Number
          _SettingSection(
            title: 'Monitor Number *',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Receive progress updates via SMS (required)',
                  style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _monitorCtrl,
                        decoration: const InputDecoration(
                          hintText: '09XXXXXXXXX',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: (v) => setState(() => _monitorNumber = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Consumer<MessagingProvider>(
                      builder: (context, provider, _) => PopupMenuButton<MonitorNumber>(
                        icon: const Icon(Icons.history_rounded),
                        tooltip: 'Saved numbers',
                        onSelected: (number) {
                          setState(() {
                            _monitorNumber = number.phoneNumber;
                            _monitorCtrl.text = number.phoneNumber;
                          });
                        },
                        itemBuilder: (_) {
                          if (provider.monitorNumbers.isEmpty) {
                            return [const PopupMenuItem(enabled: false, child: Text('No saved numbers'))];
                          }
                          return provider.monitorNumbers.map((n) =>
                            PopupMenuItem(
                              value: n,
                              child: Text(n.label != null
                                  ? '${n.label} (${n.phoneNumber})'
                                  : n.phoneNumber),
                            ),
                          ).toList();
                        },
                      ),
                    ),
                  ],
                ),
                if (_monitorNumber?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _saveMonitorNumber,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save this number'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _progressNotifyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Progress notify after N messages',
                    hintText: '15',
                    helperText: 'Send progress SMS to monitor number after this many messages (0 = off)',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    final val = int.tryParse(v) ?? 0;
                    setState(() => _progressNotifyAfter = val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _canStartSending {
    final license = context.read<LicenseProvider>();
    if (license.status != LicenseStatus.active &&
        license.status != LicenseStatus.cached) {
      return false;
    }
    if (_saving || !_testSent) return false;
    if (_totalUnsent == 0) return false;
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start < 1 || end < 1) return false;
    if (start > end) return false;
    if (end > _totalUnsent) return false;
    return true;
  }

  String _getSendButtonLabel() {
    final license = context.read<LicenseProvider>();
    if (license.status != LicenseStatus.active &&
        license.status != LicenseStatus.cached) {
      return 'License Required';
    }
    if (_saving) return 'Sending...';
    if (!_testSent) return 'Test send first';
    if (_totalUnsent == 0) return 'No unsent contacts';
    return 'Start Bulk Send (${_rangeEnd - _rangeStart + 1} targets)';
  }

  bool _saving = false;

  void _saveMonitorNumber() async {
    if (_monitorNumber == null || _monitorNumber!.isEmpty) return;
    await context.read<MessagingProvider>().saveMonitorNumber(_monitorNumber!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number saved'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _loadNetworkCounts() async {
    final counts = await context
        .read<MessagingProvider>()
        .getUnsentNetworkCounts(widget.campaign.id!);
    if (!mounted) return;
    setState(() => _networkCounts = counts);
  }

  Future<void> _loadUnsentCount() async {
    final count = await context
        .read<MessagingProvider>()
        .getUnsentCount(widget.campaign.id!, network: _targetNetwork);
    if (!mounted) return;
    setState(() {
      _totalUnsent = count;
      _rangeEnd = count;
      _rangeEndCtrl.text = count.toString();
    });
  }

  void _testSend() {
    if (_selectedGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one message group first')),
      );
      return;
    }
    if (_monitorNumber == null || _monitorNumber!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a monitor number first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: _monitorNumber);
        return AlertDialog(
          title: const Text('Test Send'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Send to number',
                  hintText: '09XXXXXXXXX',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Text('A test message will be sent to verify your setup.',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final number = ctrl.text.trim();
                if (number.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a phone number')),
                  );
                  return;
                }
                Navigator.pop(context);
                try {
                  // Load first note from selected groups as test message
                  String testMessage = 'SmsGo test message';
                  for (final group in _selectedGroups) {
                    final notes = await context.read<NotesProvider>().getNotesByGroup(group);
                    if (notes.isNotEmpty) {
                      testMessage = notes.first.content;
                      break;
                    }
                  }
                  // Replace {username} with actual lead name from campaign
                  final leads = await LeadRepository().getUnsent(widget.campaign.id!);
                  final leadName = leads.isNotEmpty ? (leads.first.name ?? '') : '';
                  testMessage = testMessage.replaceAll('{username}', leadName);

                  // Create conversation (session_id=null) and outgoing message record
                  final db = await AppDatabase.instance.database;
                  final convRepo = ConversationRepository(db);
                  final convId = await convRepo.createConversation(null, number);
                  await convRepo.addMessage(convId, 'out', testMessage, status: 'sending');

                  await SmsGateway.sendSms(
                    to: number,
                    message: testMessage,
                    simSlot: _simSlot == 'SIM 2' ? 1 : 0,
                  );
                  setState(() => _testSent = true);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Test message sent! You can now start bulk sending.'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Test send failed: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Send Test'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startSending() async {
    if (_selectedGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one message group'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_monitorNumber == null || _monitorNumber!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monitor number is required'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (!_testSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please test send first'), backgroundColor: AppColors.error),
      );
      return;
    }
    // Range validation
    if (_totalUnsent == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available targets to send to'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_rangeStart < 1 || _rangeEnd < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and End numbers must be at least 1'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_rangeStart > _rangeEnd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start number must not be greater than End number'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_rangeEnd > _totalUnsent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('End number must not exceed $_totalUnsent'), backgroundColor: AppColors.error),
      );
      return;
    }
    final rangeCount = _rangeEnd - _rangeStart + 1;
    if (rangeCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected range contains no targets'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await context.read<MessagingProvider>().startSending(
        campaign: widget.campaign,
        simSlot: _simSlot,
        targetNetwork: _targetNetwork,
        messageMode: _messageMode,
        selectedGroups: _selectedGroups.toList(),
        sendIntervalMin: _sendIntervalMin,
        sendIntervalMax: _sendIntervalMax,
        restEnabled: _restEnabled,
        restSeconds: _restSeconds,
        restAfterCount: _restAfterCount,
        progressNotifyAfter: _progressNotifyAfter,
        monitorNumber: _monitorNumber,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onStarted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bulk send started!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SimSelector extends StatelessWidget {
  final String selected;
  final bool sim1Disabled;
  final bool sim2Disabled;
  final ValueChanged<String> onSelected;

  const _SimSelector({
    required this.selected,
    required this.sim1Disabled,
    required this.sim2Disabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _simChip('SIM 1', sim1Disabled),
        _simChip('SIM 2', sim2Disabled),
      ],
    );
  }

  Widget _simChip(String label, bool disabled) {
    final isSelected = selected == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: disabled ? null : (_) => onSelected(label),
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: disabled
            ? Colors.grey
            : (isSelected ? AppColors.primary : null),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _NetworkTargetChips extends StatelessWidget {
  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onSelected;

  const _NetworkTargetChips({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppConstants.networks.map((network) {
        final count = _countFor(network);
        final isSelected = selected == network;
        return ChoiceChip(
          label: Text('$network ($count)'),
          selected: isSelected,
          onSelected: (_) => onSelected(network),
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : null,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        );
      }).toList(),
    );
  }

  int _countFor(String network) {
    if (network == AppConstants.networkAll) {
      return counts.values.fold(0, (sum, count) => sum + count);
    }
    return counts[network] ?? 0;
  }
}
