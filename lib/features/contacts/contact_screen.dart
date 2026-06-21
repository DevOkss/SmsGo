import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_theme.dart';
import '../../core/constants/phone_utils.dart';
import '../../core/widget/app_widgets.dart';
import '../../models/lead.dart';
import '../../providers/contacts_provider.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          Selector<ContactsProvider, bool>(
            selector: (_, provider) => provider.showRepliedOnly,
            builder: (context, showRepliedOnly, __) => IconButton(
              icon: Icon(showRepliedOnly
                  ? Icons.filter_list_off_rounded
                  : Icons.filter_list_rounded),
              tooltip: showRepliedOnly ? 'Show all' : 'Replied only',
              onPressed: () => context.read<ContactsProvider>().toggleRepliedFilter(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or number...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: Consumer<ContactsProvider>(
              builder: (context, provider, _) {
                if (provider.loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                var contacts = provider.filtered;
                if (_search.isNotEmpty) {
                  contacts = contacts.where((c) =>
                    c.phoneNumber.contains(_search) ||
                    (c.name?.toLowerCase().contains(_search) ?? false),
                  ).toList();
                }

                if (contacts.isEmpty) {
                  return EmptyState(
                    icon: Icons.contacts_outlined,
                    title: provider.showRepliedOnly ? 'No replies yet' : 'No contacts yet',
                    subtitle: provider.showRepliedOnly
                        ? 'Replied numbers will appear here.'
                        : 'Contacted numbers will appear here after sending.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ContactCard(lead: contacts[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    try {
      final path = await context.read<ContactsProvider>().export();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $path'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class _ContactCard extends StatelessWidget {
  final Lead lead;

  const _ContactCard({required this.lead});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(
              (lead.name?.isNotEmpty == true
                  ? lead.name![0]
                  : lead.phoneNumber[0]).toUpperCase(),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lead.name?.isNotEmpty == true)
                  Text(lead.name!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    )),
                Text(PhoneUtils.formatDisplay(lead.phoneNumber),
                  style: Theme.of(context).textTheme.bodyMedium),
                if (lead.replied && lead.replyMessage != null) ...[
                  const SizedBox(height: 4),
                  Text('↩ ${lead.replyMessage}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NetworkBadge(network: lead.network),
              const SizedBox(height: 4),
              if (lead.replied)
                const StatusBadge(label: 'REPLIED', color: AppColors.success)
              else if (lead.sent)
                const StatusBadge(label: 'SENT', color: AppColors.info),
            ],
          ),
        ],
      ),
    );
  }
}