import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../models/campaign.dart';
import '../../models/sending_session.dart';
import '../../providers/dashboard_provider.dart';
import '../../services/device_sim_gateway.dart';
import '../../services/sms_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<DashboardProvider>().load(),
          ),
        ],
      ),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: provider.load,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _StatsRow(
                  campaigns: provider.totalCampaigns,
                  sent: provider.totalSent,
                  active: provider.activeSessions.length,
                ),
                const SizedBox(height: 20),
                const _DeviceSimStatusSection(),
                if (provider.activeSessions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'Active Sendings'),
                  const SizedBox(height: 10),
                  ...provider.activeSessions.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ActiveSessionCard(session: s, dispatchedCount: provider.dispatchedCounts[s.id] ?? 0),
                  )),
                ],
                const SizedBox(height: 20),
                const SectionHeader(title: 'Campaigns'),
                const SizedBox(height: 10),
                if (provider.campaigns.isEmpty)
                  const EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No campaigns yet',
                    subtitle: 'Create a campaign from the Campaigns tab to get started.',
                  )
                else
                  ...provider.campaigns.take(5).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CampaignSummaryTile(campaign: c),
                  )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int campaigns;
  final int sent;
  final int active;

  const _StatsRow({required this.campaigns, required this.sent, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatItem(label: 'Campaigns', value: '$campaigns', icon: Icons.campaign_rounded, color: AppColors.primary)),
        const SizedBox(width: 8),
        Expanded(child: _StatItem(label: 'Total Sent', value: '$sent', icon: Icons.send_rounded, color: AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _StatItem(label: 'Active', value: '$active', icon: Icons.play_circle_outline_rounded, color: AppColors.warning)),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final SendingSession session;
  final int dispatchedCount;

  const _ActiveSessionCard({required this.session, this.dispatchedCount = 0});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campaign #${session.campaignId}',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${session.simSlot} · ${session.targetNetwork}',
                      style: Theme.of(context).textTheme.bodySmall),
                    if (session.monitorNumber != null && session.monitorNumber!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Monitor: ${session.monitorNumber}',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  StatusBadge(
                    label: session.stopped
                        ? 'STOPPED'
                        : (!session.running && !session.paused && (session.sentCount + session.failedCount >= session.totalTargets))
                            ? 'COMPLETED'
                            : (session.running ? 'RUNNING' : (session.paused ? 'PAUSED' : 'STOPPED')),
                    color: session.stopped
                        ? AppColors.darkSubtext
                        : (!session.running && !session.paused && (session.sentCount + session.failedCount >= session.totalTargets))
                            ? AppColors.success
                            : (session.running ? AppColors.success : AppColors.darkSubtext),
                  ),
                  if (session.running || session.paused) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.stop_circle_rounded, color: AppColors.error, size: 20),
                      onPressed: () => context.read<DashboardProvider>().stopSession(session.id!),
                      tooltip: 'Stop',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressRow(
            sent: session.sentCount,
            total: session.totalTargets,
            failed: session.failedCount,
            dispatched: dispatchedCount,
          ),
        ],
      ),
    );
  }
}

class _DeviceSimStatusSection extends StatefulWidget {
  const _DeviceSimStatusSection();

  @override
  State<_DeviceSimStatusSection> createState() => _DeviceSimStatusSectionState();
}

class _DeviceSimStatusSectionState extends State<_DeviceSimStatusSection> {
  bool _loading = true;
  List<Map<String, dynamic>> _sims = const [];
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _simSub;
  DateTime? _lastSimUpdate;
  Timer? _throttleTimer;
  Map<String, dynamic>? _pendingUpdate;

  @override
  void initState() {
    super.initState();
    _load();
    _simSub = SmsService.instance.simStream.listen((update) {
      if (!mounted) return;
      _pendingUpdate = update;
      final now = DateTime.now();
      if (_lastSimUpdate == null || now.difference(_lastSimUpdate!) >= const Duration(seconds: 5)) {
        _lastSimUpdate = now;
        _applySimUpdate(_pendingUpdate!);
      } else {
        _throttleTimer?.cancel();
        _throttleTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _pendingUpdate != null) {
            _lastSimUpdate = DateTime.now();
            _applySimUpdate(_pendingUpdate!);
          }
        });
      }
    });
  }

  void _applySimUpdate(Map<String, dynamic> update) {
    setState(() {
      try {
        final subId = update['subscriptionId'];
        if (subId == null) return;
        for (var i = 0; i < _sims.length; i++) {
          final sim = _sims[i];
          if (sim['subscriptionId'] == subId) {
            final newSim = Map<String, dynamic>.from(sim);
            if (update.containsKey('signalDbm')) newSim['signalDbm'] = update['signalDbm'];
            if (update.containsKey('signalAsu')) newSim['signalAsu'] = update['signalAsu'];
            _sims = List<Map<String, dynamic>>.from(_sims);
            _sims[i] = newSim;
            break;
          }
        }
      } catch (e) {
        // ignore
      }
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _simSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sims = await DeviceSimGateway.getDeviceSimStatus();
      if (!mounted) return;
      setState(() {
        _sims = sims;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Device SIM Status'),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text('Failed to load: $_error', style: Theme.of(context).textTheme.bodySmall)
        else if (_sims.isEmpty)
          const EmptyState(
            icon: Icons.sim_card_outlined,
            title: 'No SIM info',
            subtitle: 'Unable to read SIM information.',
          )
        else
          ..._sims.map((sim) {
            final slotIndex = (sim['slotIndex'] ?? sim['slot'] ?? sim['index'] ?? '').toString();
            final carrier = (sim['carrier'] ?? '').toString();
            final phoneNumber = (sim['phoneNumber'] ?? '').toString();

            int? signalDbm;
            final rawDbm = sim['signalDbm'];
            if (rawDbm is int) {
              signalDbm = rawDbm;
            } else if (rawDbm is num) {
              signalDbm = rawDbm.toInt();
            } else if (rawDbm is String) {
              signalDbm = int.tryParse(rawDbm);
            }

            int? signalAsu;
            final rawAsu = sim['signalAsu'];
            if (rawAsu is int) {
              signalAsu = rawAsu;
            } else if (rawAsu is num) {
              signalAsu = rawAsu.toInt();
            } else if (rawAsu is String) {
              signalAsu = int.tryParse(rawAsu);
            }

            final signal = <String, dynamic>{
              'signalDbm': signalDbm,
              'signalAsu': signalAsu,
            };

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SimTile(
                slotIndex: slotIndex,
                carrier: carrier,
                phoneNumber: phoneNumber,
                signal: signal,
              ),
            );
          }),
      ],
    );
  }
}

class _SimTile extends StatelessWidget {
  final String slotIndex;
  final String carrier;
  final String phoneNumber;
  final Map<String, dynamic> signal;

  const _SimTile({
    required this.slotIndex,
    required this.carrier,
    required this.phoneNumber,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.sim_card_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SIM $slotIndex', style: Theme.of(context).textTheme.titleSmall),
                Text('Carrier: ${carrier.isEmpty ? 'Unknown' : carrier}', style: Theme.of(context).textTheme.bodySmall),
                Text('Number: ${phoneNumber.isEmpty ? 'Unknown' : phoneNumber}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          _SignalBars(signal),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final Object? signal;
  const _SignalBars(this.signal);

  @override
  Widget build(BuildContext context) {
    int? dbm;
    final m = signal is Map ? (signal as Map<dynamic, dynamic>?) : null;
    if (m != null) {
      final dbmObj = (m as Map<dynamic, dynamic>?)?['signalDbm'];
      if (dbmObj is int) dbm = dbmObj;
    }

    if (dbm == null) {
      int? asu;
      if (signal is Map) {
        final maybeAsuObj = (signal as Map<dynamic, dynamic>?)?['signalAsu'];
        if (maybeAsuObj is int) asu = maybeAsuObj;
      }
      if (asu != null) {
        dbm = -113 + (2 * asu);
      }
    }

    int bars;
    if (dbm == null) {
      bars = 0;
    } else if (dbm >= -70) {
      bars = 3;
    } else if (dbm >= -85) {
      bars = 2;
    } else if (dbm >= -100) {
      bars = 1;
    } else {
      bars = 0;
    }

    Color barColor(int index) {
      return index < bars ? AppColors.success : AppColors.darkSubtext.withValues(alpha: 0.3);
    }

    return SizedBox(
      width: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) => Expanded(
          child: Container(
            height: 8.0 + (i * 4),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: barColor(i),
            ),
          ),
        )),
      ),
    );
  }
}

class _CampaignSummaryTile extends StatelessWidget {
  final Campaign campaign;

  const _CampaignSummaryTile({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final pct = campaign.totalLeads > 0
        ? (campaign.sentCount / campaign.totalLeads * 100).toStringAsFixed(0)
        : '0';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(campaign.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('${campaign.sentCount} / ${campaign.totalLeads} sent',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text('$pct%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: campaign.totalLeads > 0 && campaign.sentCount >= campaign.totalLeads
                    ? AppColors.success
                    : AppColors.primary,
              )),
          ],
        ),
      ),
    );
  }
}
