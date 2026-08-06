// lib/features/notifications/presentation/notifications_screen.dart

import 'package:flutter/material.dart';

import '../../../core/widgets/custom_loader.dart';
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
    try {
      final list = await widget.repository.fetchAll();
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openNotification(AppNotification n) async {
    if (!n.isRead) {
      // Optimistically mark as read in the UI instantly for a snappy feel
      setState(() {
        final index = _notifications.indexWhere((element) => element.id == n.id);
        if (index != -1) {
          _notifications[index] = AppNotification(
            id: n.id,
            loanId: n.loanId,
            title: n.title,
            body: n.body,
            isRead: true,
            createdAt: n.createdAt,
          );
        }
      });
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
      _load(); // Reload to catch any changes that happened in the detail screen
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_notifications.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: hasUnread 
                    ? () async {
                        setState(() {
                          // Optimistic UI update
                          _notifications = _notifications.map((n) => AppNotification(
                            id: n.id, loanId: n.loanId, title: n.title, body: n.body, isRead: true, createdAt: n.createdAt,
                          )).toList();
                        });
                        await widget.repository.markAllRead();
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.done_all_rounded, size: 20),
                label: const Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: hasUnread ? scheme.primary : scheme.onSurface.withOpacity(0.3),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CustomLoader(size: 56, color: scheme.primary))
          : _notifications.isEmpty
              ? _StaggeredFadeIn(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                              child: Icon(Icons.notifications_off_rounded, size: 48, color: scheme.onSurface.withOpacity(0.2)),
                            ),
                            const SizedBox(height: 20),
                            const Text('You\'re all caught up!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(
                              'You have no new notifications right now.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: scheme.onSurface.withOpacity(0.6), height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: scheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                    itemCount: _notifications.length,
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      return _StaggeredFadeIn(
                        index: i,
                        child: _NotificationCard(
                          notification: n,
                          timeAgo: _timeAgo(n.createdAt),
                          onTap: () => _openNotification(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final String timeAgo;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.timeAgo,
    required this.onTap,
  });

  // Helper to dynamically style the icon based on notification context
  (IconData, Color) _getIconDesign(String title, ColorScheme scheme) {
    final t = title.toLowerCase();
    if (t.contains('approve') || t.contains('confirm') || t.contains('complete')) {
      return (Icons.check_circle_rounded, scheme.primary);
    } else if (t.contains('reject') || t.contains('decline') || t.contains('return')) {
      return (Icons.cancel_rounded, const Color(0xFFD9534F));
    } else if (t.contains('guarantor') || t.contains('request')) {
      return (Icons.shield_rounded, const Color(0xFFE9A63C));
    } else if (t.contains('disburse') || t.contains('deduct') || t.contains('repayment')) {
      return (Icons.account_balance_wallet_rounded, const Color(0xFF58B982));
    } else if (t.contains('new') || t.contains('submit')) {
      return (Icons.post_add_rounded, const Color(0xFF4A90E2));
    }
    return (Icons.notifications_rounded, scheme.onSurface.withOpacity(0.6));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRead = notification.isRead;
    
    final design = _getIconDesign(notification.title, scheme);
    final iconData = design.$1;
    final iconColor = isRead ? scheme.onSurface.withOpacity(0.4) : design.$2;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isRead ? Theme.of(context).cardTheme.color : scheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRead ? scheme.outlineVariant.withOpacity(0.4) : scheme.primary.withOpacity(0.3),
          width: isRead ? 1 : 1.5,
        ),
        boxShadow: isRead ? [] : [
          BoxShadow(color: scheme.primary.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRead ? scheme.surfaceContainerHighest.withOpacity(0.3) : iconColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconData, size: 22, color: iconColor),
                ),
                const SizedBox(width: 16),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                color: isRead ? scheme.onSurface.withOpacity(0.8) : scheme.onSurface,
                                letterSpacing: isRead ? 0 : -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                              color: isRead ? scheme.onSurface.withOpacity(0.5) : scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface.withOpacity(isRead ? 0.6 : 0.8),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                
                // Unread Dot Indicator
                if (!isRead) ...[
                  const SizedBox(width: 12),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.5), blurRadius: 6)],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A lightweight wrapper to provide a staggered fade & slide entrance animation.
class _StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;

  const _StaggeredFadeIn({required this.child, required this.index});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}