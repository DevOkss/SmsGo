import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widget/app_widgets.dart';
import '../../models/note.dart';
import '../../providers/notes_provider.dart';

class _HighlightEditingController extends TextEditingController {
  static final _usernamePattern = RegExp(r'\{username\}');

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final textValue = text;
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in _usernamePattern.allMatches(textValue)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: textValue.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < textValue.length) {
      spans.add(TextSpan(text: textValue.substring(lastEnd)));
    }

    return TextSpan(
      children: spans.isEmpty ? [TextSpan(text: textValue)] : spans,
      style: style ?? DefaultTextStyle.of(context).style,
    );
  }
}

class NoteGroupScreen extends StatefulWidget {
  final String groupName;
  const NoteGroupScreen({super.key, required this.groupName});

  @override
  State<NoteGroupScreen> createState() => _NoteGroupScreenState();
}

class _NoteGroupScreenState extends State<NoteGroupScreen> {
  static final _linkPattern = RegExp(
    r'(https?://[^\s]+|[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s]*)?)',
    caseSensitive: false,
  );
  static final _blockedPattern = RegExp(r'https?://[^\s]+');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotesProvider>().loadGroup(widget.groupName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'group_notes_fab',
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Note'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Consumer<NotesProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.notes.isEmpty) {
            return const EmptyState(
              icon: Icons.note_outlined,
              title: 'No notes yet',
              subtitle: 'Add a note to use as a message for bulk sending.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.notes.length,
            itemBuilder: (context, i) {
              final note = provider.notes[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NoteCard(
                  note: note,
                  onEdit: () => _showAddDialog(editing: note),
                  onDelete: () => _confirmDelete(note),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddDialog({Note? editing}) {
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final contentCtrl = _HighlightEditingController()..text = editing?.content ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final content = contentCtrl.text;
          final charCount = content.length;
          final hasLink = _containsLink(content);
          final hasBlockedLink = _containsBlockedLink(content);
          final canSave = titleCtrl.text.trim().isNotEmpty &&
              contentCtrl.text.trim().isNotEmpty &&
              !hasBlockedLink;

          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(editing == null ? 'New Note' : 'Edit Note',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Promo 1'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Type your SMS message...',
                    helperText: 'Use {username} to insert the lead\'s name',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$charCount characters',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: charCount > 160 ? AppColors.error : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (hasLink) ...[
                      Icon(Icons.link_rounded, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Link detected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasBlockedLink) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Links with http:// or https:// are not allowed',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: canSave
                      ? () async {
                          if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;
                          final provider = context.read<NotesProvider>();
                          if (editing != null) {
                            await provider.update(editing.copyWith(
                              title: titleCtrl.text.trim(),
                              content: contentCtrl.text.trim(),
                            ));
                          } else {
                            await provider.create(
                              titleCtrl.text.trim(),
                              contentCtrl.text.trim(),
                              widget.groupName,
                            );
                          }
                          await provider.loadGroup(widget.groupName);
                          if (mounted) Navigator.pop(ctx);
                        }
                      : null,
                  child: Text(editing == null ? 'Add Note' : 'Save Changes'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _containsLink(String text) {
    return _linkPattern.hasMatch(text);
  }

  bool _containsBlockedLink(String text) {
    return _blockedPattern.hasMatch(text);
  }

  Future<void> _confirmDelete(Note note) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Delete Note',
      message: 'Delete "${note.title}"?',
    );
    if (confirm && mounted) {
      await context.read<NotesProvider>().delete(note.id!);
      await context.read<NotesProvider>().loadGroup(widget.groupName);
    }
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteCard({required this.note, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(note.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Edit'),
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
          const SizedBox(height: 6),
          Text(note.content,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            '${note.content.length} characters',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
