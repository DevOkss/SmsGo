import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/imported_conversations_provider.dart';
import 'conversation_detail_screen.dart';

class ImportedActiveConversationsScreen extends StatefulWidget {
  final int sessionId;
  const ImportedActiveConversationsScreen({super.key, required this.sessionId});

  @override
  State<ImportedActiveConversationsScreen> createState() => _ImportedActiveConversationsScreenState();
}

class _ImportedActiveConversationsScreenState extends State<ImportedActiveConversationsScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ImportedConversationsProvider(widget.sessionId),
      child: Builder(
        builder: (context) {
          final provider = context.watch<ImportedConversationsProvider>();

          return Scaffold(
            appBar: AppBar(
                title: const Text('Imported Conversations'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Session ID: ${widget.sessionId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Imported (Active)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ElevatedButton.icon(
                        onPressed: provider.loading
                            ? null
                            : () async {
                                await provider.load();
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: provider.loading
                      ? const Center(child: CircularProgressIndicator())
                      : (provider.data?.active.isEmpty ?? true)
                          ? const Center(
                              child: Text('No imported active conversations yet.'),
                            )
                          : ListView.builder(
                              itemCount: provider.data!.active.length,
                              itemBuilder: (context, i) {
                                final c = provider.data!.active[i];
                                return ListTile(
                                  title: Text(c.phoneNumber),
                                  subtitle: Text(
                                    c.lastMessage ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ConversationDetailScreen(conversation: c),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

