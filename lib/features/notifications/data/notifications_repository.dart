// lib/features/notifications/data/notifications_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  final String id;
  final String? loanId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.loanId,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        loanId: map['loan_id'] as String?,
        title: map['title'] as String,
        body: map['body'] as String,
        isRead: map['is_read'] as bool,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class NotificationsRepository {
  NotificationsRepository(this._client);
  final SupabaseClient _client;

  Future<List<AppNotification>> fetchAll() async {
    final rows = await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List).map((r) => AppNotification.fromMap(r)).toList();
  }

  Future<int> fetchUnreadCount() async {
    final rows = await _client.from('notifications').select('id').eq('is_read', false);
    return (rows as List).length;
  }

  Future<void> markRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    await _client.from('notifications').update({'is_read': true}).eq('is_read', false);
  }
}
