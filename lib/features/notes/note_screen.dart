import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../providers/notes_provider.dart';
import 'note_group_screen.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotesProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes / Spiels'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notes_fab',
        onPressed: _showCreateGroupDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer<NotesProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = provider.groups;

          if (groups.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_outlined,
              title: 'No groups yet',
              subtitle: 'Create a group to organize your messages for bulk sending.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              final name = group['group_name'] as String;
              final count = group['note_count'] as int;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _GroupCard(
                  name: name,
                  noteCount: count,
                  onTap: () => _openGroup(name),
                  onRename: () => _showRenameGroupDialog(name),
                  onDelete: () => _confirmDeleteGroup(name),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openGroup(String groupName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<NotesProvider>(),
          child: NoteGroupScreen(groupName: groupName),
        ),
      ),
    ).then((_) {
      // Reload groups when coming back (note counts may have changed)
      context.read<NotesProvider>().load();
    });
  }

  void _showCreateGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g. 1SJL, Promo A',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _createGroup(ctx, ctrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _createGroup(ctx, ctrl),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createGroup(BuildContext ctx, TextEditingController ctrl) async {
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(ctx);
    await context.read<NotesProvider>().createGroup(name);
    _openGroup(name);
  }

  void _showRenameGroupDialog(String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group Name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == currentName) {
                Navigator.pop(ctx);
                return;
              }
              await context.read<NotesProvider>().renameGroup(currentName, newName);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteGroup(String groupName) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Delete Group',
      message: 'Delete group "$groupName" and all its notes?',
    );
    if (confirm && mounted) {
      await context.read<NotesProvider>().deleteGroup(groupName);
    }
  }
}

class _GroupCard extends StatelessWidget {
  final String name;
  final int noteCount;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _GroupCard({
    required this.name,
    required this.noteCount,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.folder_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 2),
                Text(
                  '$noteCount note${noteCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (val) {
              if (val == 'rename') onRename();
              if (val == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Rename'),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_rounded, size: 18, color: AppColors.error),
                  SizedBox(width: 10),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
