// lib/features/notifications/presentation/notifications_screen.dart

import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../../loans/data/loan_repository.dart';
import '../../loans/presentation/loan_detail_screen.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repository,
    required this.loanRepository,
    required this.profile,
  });

  final NotificationsRepository repository;
  final LoanRepository loanRepository;
  final Profile profile;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await widget.repository.fetchAll();
    if (!mounted) return;
    setState(() {
      _notifications = list;
      _loading = false;
    });
  }

  Future<void> _openNotification(AppNotification n) async {
    if (!n.isRead) {
      await widget.repository.markRead(n.id);
    }
    if (n.loanId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoanDetailScreen(
            repository: widget.loanRepository,
            profile: widget.profile,
            loanId: n.loanId!,
          ),
        ),
      );
    }
    _load();
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.repository.markAllRead();
              _load();
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Text('No notifications yet', style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      return ListTile(
                        onTap: () => _openNotification(n),
                        leading: Icon(
                          n.isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                          color: n.isRead ? scheme.onSurfaceVariant : scheme.primary,
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w700),
                        ),
                        subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(_timeAgo(n.createdAt),
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      );
                    },
                  ),
                ),
    );
  }
}
