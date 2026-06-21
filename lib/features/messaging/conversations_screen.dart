import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../database/database.dart';
import '../../models/conversation.dart';
import '../../repositories/conversation_repository.dart';
import '../../services/sms_service.dart';
import 'conversation_detail_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, dynamic>> _allConversations = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _filter = 'all'; // all, unread, read
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  StreamSubscription<Map<String, dynamic>>? _sendResultSub;
  int _unreadCount = 0;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Subscribe to real-time incoming SMS events with debounce
    _incomingSub = SmsService.instance.incomingEvents.listen((_) {
      _debouncedLoad();
    });
    // Subscribe to send results for realtime status updates with debounce
    _sendResultSub = SmsService.instance.sendEvents.listen((_) {
      _debouncedLoad();
    });
  }

  void _debouncedLoad() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _incomingSub?.cancel();
    _sendResultSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await AppDatabase.instance.database;
    final repo = ConversationRepository(db);

    bool? unreadFilter;

    switch (_filter) {
      case 'unread':
        unreadFilter = true;
        break;
      case 'read':
        unreadFilter = false;
        break;
    }

    final rows = await repo.getAllConversations(
      unread: unreadFilter,
    );
    _unreadCount = await repo.getUnreadCount();

    if (!mounted) return;
    setState(() {
      _allConversations = rows;
      _applySearch();
      _loading = false;
    });
  }

  void _applySearch() {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) {
      _filtered = List.from(_allConversations);
    } else {
      _filtered = _allConversations.where((r) {
        final phone = (r['phone_number'] as String? ?? '').toLowerCase();
        final msg = (r['last_message'] as String? ?? '').toLowerCase();
        return phone.contains(q) || msg.contains(q);
      }).toList();
    }
  }

  void _onFilterChanged(String filter) {
    setState(() => _filter = filter);
    _load();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applySearch();
    });
  }

  Future<void> _deleteAllConversations() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete all conversations?',
      message: 'This will permanently delete ALL conversations and their messages. This cannot be undone.',
      confirmLabel: 'Delete All',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;

    final db = await AppDatabase.instance.database;
    final repo = ConversationRepository(db);
    await repo.deleteAllConversations();
    _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All conversations deleted')),
      );
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _filtered.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_filtered.map((r) => r['id'] as int));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete ${_selectedIds.length} conversation(s)?',
      message: 'This will permanently delete the selected conversations and all their messages.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;

    final db = await AppDatabase.instance.database;
    final repo = ConversationRepository(db);
    for (final id in _selectedIds) {
      await repo.deleteConversation(id);
    }
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
    _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected conversations deleted')),
      );
    }
  }

  Future<void> _startNewConversation() async {
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Conversation'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a phone number to start messaging.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  hintText: '09XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone_rounded),
                  labelText: 'Phone Number',
                ),
                keyboardType: TextInputType.phone,
                autofocus: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a phone number';
                  if (v.trim().length < 10) return 'Enter a valid phone number';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, phoneCtrl.text.trim());
              }
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    final phone = normalizePhone(result);
    final db = await AppDatabase.instance.database;
    final convRepo = ConversationRepository(db);

    // Check if conversation already exists for this phone number
    // Search by normalized number AND by raw number (handles old un-normalized data)
    // Also check across all conversation types (standalone and campaign)
    final existing = await db.rawQuery(
      "SELECT * FROM conversations WHERE phone_number = ? OR phone_number = ? ORDER BY created_at DESC LIMIT 1",
      [phone, result.trim()],
    );

    if (existing.isNotEmpty) {
      // Already exists — just open it
      final conv = Conversation.fromMap(existing.first);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(conversation: conv),
        ),
      );
      _load();
      return;
    }

    // Create the conversation (no campaign needed)
    final convId = await convRepo.createConversation(null, phone);

    if (!mounted) return;
    final conv = Conversation(
      id: convId,
      sessionId: null,
      phoneNumber: phone,
      createdAt: DateTime.now().toIso8601String(),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(conversation: conv),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Conversations'),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _toggleSelectMode,
              )
            : null,
        actions: _selectMode
            ? [
                IconButton(
                  icon: Icon(
                    _selectedIds.length == _filtered.length
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                  ),
                  tooltip: _selectedIds.length == _filtered.length ? 'Deselect All' : 'Select All',
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_rounded, color: AppColors.error),
                  tooltip: 'Delete Selected',
                  onPressed: _deleteSelected,
                ),
              ]
            : [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter',
            onSelected: _onFilterChanged,
            itemBuilder: (_) => [
              _buildFilterItem('all', 'All'),
              _buildFilterItem('unread', 'Unread ($_unreadCount)'),
              _buildFilterItem('read', 'Read'),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'delete_all') _deleteAllConversations();
              if (v == 'select') _toggleSelectMode();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'select',
                child: Row(
                  children: [
                    const Icon(Icons.checklist_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Text('Select'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 20),
                    SizedBox(width: 8),
                    Text('Delete All'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Conversation',
        onPressed: _startNewConversation,
        child: const Icon(Icons.chat_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? EmptyState(
                  icon: Icons.forum_outlined,
                  title: _searchQuery.isNotEmpty
                      ? 'No matching conversations'
                      : 'No conversations yet',
                  subtitle: _searchQuery.isNotEmpty
                      ? 'Try a different search term.'
                      : 'Conversations will appear here as messages are sent and received.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, i) {
                      final row = _filtered[i];
                      final convId = row['id'] as int;
                      return _ConversationTile(
                        row: row,
                        selected: _selectedIds.contains(convId),
                        selectMode: _selectMode,
                        onTap: _selectMode
                            ? () => _toggleSelection(convId)
                            : () async {
                                final conv = Conversation.fromMap(row);
                                final simSlot = row['sim_slot'] as String?;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConversationDetailScreen(
                                      conversation: conv,
                                      simSlot: simSlot,
                                    ),
                                  ),
                                );
                                _load();
                              },
                        onLongPress: () {
                          if (!_selectMode) {
                            _selectMode = true;
                            _selectedIds.add(convId);
                            setState(() {});
                          }
                        },
                      );
                    },
                  ),
      ),
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

class _StatusIconSmall extends StatelessWidget {
  final String? status;
  const _StatusIconSmall({this.status});

  @override
  Widget build(BuildContext context) {
    final s = (status ?? '').toLowerCase();
    if (s == 'sending') {
      return const Icon(Icons.hourglass_top_rounded, size: 13, color: Colors.amber);
    }
    if (s == 'sent') {
      return const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success);
    }
    if (s == 'failed') {
      return const Icon(Icons.cancel_rounded, size: 13, color: AppColors.error);
    }
    return const SizedBox.shrink();
  }
}

class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectMode;

  const _ConversationTile({
    required this.row,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final phone = row['phone_number'] as String? ?? '';
    final lastMsg = row['last_message'] as String?;
    final lastDirection = row['last_direction'] as String?;
    final unread = (row['unread'] as int? ?? 0) == 1;
    final simSlot = row['sim_slot'] as String?;
    final createdAt = row['created_at'] as String?;
    final outgoingStatus = row['outgoing_status'] as String?;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
            if (selectMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
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
                      if (simSlot != null && simSlot.isNotEmpty)
                        _SimChip(label: simSlot),
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
                      const SizedBox(width: 4),
                      if (lastDirection == 'out')
                        _StatusIconSmall(status: outgoingStatus),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
      }
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

class _SimChip extends StatelessWidget {
  final String label;
  const _SimChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isSim2 = label.contains('2');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isSim2 ? Colors.orange : AppColors.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.replaceAll('SIM ', 'S'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isSim2 ? Colors.orange.shade700 : AppColors.primary,
        ),
      ),
    );
  }
}
