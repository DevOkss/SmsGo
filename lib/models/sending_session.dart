class SendingSession {
  final int? id;
  final int campaignId;
  final String simSlot;
  final String targetNetwork;
  final String messageMode; // rotational | sequential
  final int totalTargets;
  final int sentCount;
  final int failedCount;
  final bool running;
  final bool paused;
  final bool stopped;
  final bool removed;
  final String? nextSendAt;

  final int sendInterval; // seconds
  final int sendIntervalMin; // seconds
  final int sendIntervalMax; // seconds
  final bool restEnabled;
  final int restSeconds;
  final int restAfterCount; // rest after this many sent messages (0 = disabled)
  final int progressNotifyAfter; // send progress SMS to monitor after N messages (0 = disabled)
  final String? monitorNumber;
  final String selectedGroups; // comma-separated group names
  final int rangeStart;
  final int rangeEnd;
  final String createdAt;
  final String? endedAt;

  SendingSession({
    this.id,
    required this.campaignId,
    required this.simSlot,
    required this.targetNetwork,
    required this.messageMode,
    this.totalTargets = 0,
    this.sentCount = 0,
    this.failedCount = 0,
    this.running = true,
    this.paused = false,
    this.stopped = false,
    this.removed = false,
    this.nextSendAt,
    this.sendInterval = 3,
    int? sendIntervalMin,
    int? sendIntervalMax,
    this.restEnabled = false,
    this.restSeconds = 0,
    this.restAfterCount = 0,
    this.progressNotifyAfter = 0,
    this.monitorNumber,
    this.selectedGroups = '',
    this.rangeStart = 1,
    this.rangeEnd = 0,
    required this.createdAt,
    this.endedAt,
  })  : sendIntervalMin = sendIntervalMin ?? sendInterval,
        sendIntervalMax = sendIntervalMax ?? sendInterval;

  List<String> get selectedGroupsList =>
      selectedGroups.isEmpty ? [] : selectedGroups.split(',').map((s) => s.trim()).toList();

  factory SendingSession.fromMap(Map<String, dynamic> map) => SendingSession(
        id: map['id'],
        campaignId: map['campaign_id'],
        simSlot: map['sim_slot'] ?? 'SIM 1',
        targetNetwork: map['target_network'] ?? 'All',
        messageMode: map['message_mode'] ?? 'rotational',
        totalTargets: map['total_targets'] ?? 0,
        sentCount: map['sent_count'] ?? 0,
        failedCount: map['failed_count'] ?? 0,
        running: map['running'] == 1,
        paused: (map['paused'] ?? 0) == 1,
        stopped: (map['stopped'] ?? 0) == 1,
        removed: (map['removed'] ?? 0) == 1,
        nextSendAt: map['next_send_at'],
        sendInterval: map['send_interval'] ?? 3,
        sendIntervalMin: map['send_interval_min'] ?? map['send_interval'] ?? 3,
        sendIntervalMax: map['send_interval_max'] ?? map['send_interval'] ?? 3,
        restEnabled: (map['rest_enabled'] ?? 0) == 1,
        restSeconds: map['rest_seconds'] ?? 0,
        restAfterCount: map['rest_after_count'] ?? 0,
        progressNotifyAfter: map['progress_notify_after'] ?? 0,
        monitorNumber: map['monitor_number'],
        selectedGroups: map['selected_groups'] ?? '',
        rangeStart: map['range_start'] ?? 1,
        rangeEnd: map['range_end'] ?? 0,
        createdAt: map['created_at'],
        endedAt: map['ended_at'],
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'campaign_id': campaignId,
        'sim_slot': simSlot,
        'target_network': targetNetwork,
        'message_mode': messageMode,
        'total_targets': totalTargets,
        'sent_count': sentCount,
        'failed_count': failedCount,
        'running': running ? 1 : 0,
        'paused': paused ? 1 : 0,
        'stopped': stopped ? 1 : 0,
        'removed': removed ? 1 : 0,
        'next_send_at': nextSendAt,
        'send_interval': sendInterval,
        'send_interval_min': sendIntervalMin,
        'send_interval_max': sendIntervalMax,
        'rest_enabled': restEnabled ? 1 : 0,
        'rest_seconds': restSeconds,
        'rest_after_count': restAfterCount,
        'progress_notify_after': progressNotifyAfter,
        'monitor_number': monitorNumber,
        'selected_groups': selectedGroups,
        'range_start': rangeStart,
        'range_end': rangeEnd,
        'created_at': createdAt,
        'ended_at': endedAt,
      };

  double get progress => totalTargets > 0 ? sentCount / totalTargets : 0.0;

  SendingSession copyWith({
    int? id,
    int? campaignId,
    String? simSlot,
    String? targetNetwork,
    String? messageMode,
    int? totalTargets,
    int? sentCount,
    int? failedCount,
    bool? running,
    bool? paused,
    bool? stopped,
    bool? removed,
    String? nextSendAt,
    int? sendInterval,
    int? sendIntervalMin,
    int? sendIntervalMax,
    bool? restEnabled,
    int? restSeconds,
    int? restAfterCount,
    int? progressNotifyAfter,
    String? monitorNumber,
    String? selectedGroups,
    int? rangeStart,
    int? rangeEnd,
    String? createdAt,
    String? endedAt,
  }) => SendingSession(
        id: id ?? this.id,
        campaignId: campaignId ?? this.campaignId,
        simSlot: simSlot ?? this.simSlot,
        targetNetwork: targetNetwork ?? this.targetNetwork,
        messageMode: messageMode ?? this.messageMode,
        totalTargets: totalTargets ?? this.totalTargets,
        sentCount: sentCount ?? this.sentCount,
        failedCount: failedCount ?? this.failedCount,
        running: running ?? this.running,
        paused: paused ?? this.paused,
        stopped: stopped ?? this.stopped,
        removed: removed ?? this.removed,
        nextSendAt: nextSendAt ?? this.nextSendAt,
        sendInterval: sendInterval ?? this.sendInterval,
        sendIntervalMin: sendIntervalMin ?? this.sendIntervalMin,
        sendIntervalMax: sendIntervalMax ?? this.sendIntervalMax,
        restEnabled: restEnabled ?? this.restEnabled,
        restSeconds: restSeconds ?? this.restSeconds,
        restAfterCount: restAfterCount ?? this.restAfterCount,
        progressNotifyAfter: progressNotifyAfter ?? this.progressNotifyAfter,
        monitorNumber: monitorNumber ?? this.monitorNumber,
        selectedGroups: selectedGroups ?? this.selectedGroups,
        rangeStart: rangeStart ?? this.rangeStart,
        rangeEnd: rangeEnd ?? this.rangeEnd,
        createdAt: createdAt ?? this.createdAt,
        endedAt: endedAt ?? this.endedAt,
      );
}
