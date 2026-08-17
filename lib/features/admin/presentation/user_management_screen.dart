// lib/features/admin/presentation/user_management_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/custom_loader.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _profiles = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Fetch profiles AND join the user_roles and roles tables to get the role label
      final response = await Supabase.instance.client
          .from('profiles')
          .select('''
            id, 
            full_name, 
            community_id,
            user_roles (
              roles (
                label
              )
            )
          ''')
          .order('full_name');
          
      if (!mounted) return;
      setState(() {
        _profiles = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load users: $e';
        _loading = false;
      });
    }
  }

  // 2. Secure Delete Confirmation Dialog
  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final scheme = Theme.of(context).colorScheme;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_remove_rounded, color: Color(0xFFD9534F)),
            ),
            const SizedBox(width: 12),
            const Text('Delete User?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete ${user['full_name']} from the system? This action cannot be undone.',
          style: const TextStyle(height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      try {
        // Delete the profile. (If you have cascade deletes set up in Supabase, 
        // this will also remove their user_roles and loans automatically).
        await Supabase.instance.client
            .from('profiles')
            .delete()
            .eq('id', user['id']);
            
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted successfully.')),
        );
        _fetchUsers(); // Refresh the list
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete user: $e'),
            backgroundColor: const Color(0xFFD9534F),
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _openRoleAssignment(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RoleAssignmentSheet(
        user: user,
        onRoleAssigned: _fetchUsers, 
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? Center(child: CustomLoader(size: 56, color: scheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFD9534F), height: 1.5), textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchUsers,
                  color: scheme.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _profiles.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final user = _profiles[index];
                      final isPending = user['community_id'] == null;
                      
                      // Safely parse the nested role label from the Supabase join response
                      String currentRole = 'No role assigned';
                      if (user['user_roles'] != null && (user['user_roles'] as List).isNotEmpty) {
                        final roleData = (user['user_roles'] as List).first;
                        if (roleData['roles'] != null && roleData['roles']['label'] != null) {
                          currentRole = roleData['roles']['label'];
                        }
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isPending ? const Color(0xFFE9A63C).withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.5),
                            width: isPending ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: isPending ? const Color(0xFFE9A63C).withValues(alpha: 0.15) : scheme.primary.withValues(alpha: 0.15),
                            child: Text(
                              user['full_name'].toString().isNotEmpty ? user['full_name'].toString()[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: isPending ? const Color(0xFFE9A63C) : scheme.primary, 
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            user['full_name'] ?? 'Unknown User',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              // Displays the Role Label instead of the Phone Number
                              Row(
                                children: [
                                  Icon(Icons.badge_rounded, size: 14, color: scheme.onSurface.withValues(alpha: 0.5)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      currentRole, 
                                      style: TextStyle(
                                        color: scheme.onSurface.withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isPending) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE9A63C).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Pending Assignment',
                                    style: TextStyle(color: Color(0xFFE9A63C), fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ]
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Delete User Button
                              IconButton(
                                onPressed: () => _confirmDeleteUser(user),
                                icon: Icon(Icons.delete_outline_rounded, color: const Color(0xFFD9534F).withValues(alpha: 0.8)),
                                tooltip: 'Delete User',
                              ),
                              const SizedBox(width: 4),
                              // Manage Role Button
                              FilledButton.tonal(
                                onPressed: () => _openRoleAssignment(user),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Manage', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------
// Bottom Sheet for Assigning Roles
// ---------------------------------------------------------
class _RoleAssignmentSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onRoleAssigned;

  const _RoleAssignmentSheet({required this.user, required this.onRoleAssigned});

  @override
  State<_RoleAssignmentSheet> createState() => _RoleAssignmentSheetState();
}

class _RoleAssignmentSheetState extends State<_RoleAssignmentSheet> {
  bool _saving = false;
  String? _selectedRoleId;
  List<Map<String, dynamic>> _availableRoles = [];
  bool _isLoadingRoles = true;
  
  // Hardcoded for testing. Update to your actual community ID!
  final String _defaultCommunityId = '915b96f5-57c2-424e-9b51-dca2b9adfcdb'; 

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

  Future<void> _fetchRoles() async {
    try {
      final response = await Supabase.instance.client.from('roles').select('id, label');
      if (mounted) {
        setState(() {
          _availableRoles = List<Map<String, dynamic>>.from(response);
          _isLoadingRoles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load roles: $e'),
            backgroundColor: const Color(0xFFE9A63C),
          ),
        );
        setState(() => _isLoadingRoles = false);
      }
    }
  }

  Future<void> _assignRole() async {
    if (_selectedRoleId == null) return;
    
    setState(() => _saving = true);
    
    try {
      // 1. Assign the user to the community in their profile
      await Supabase.instance.client
          .from('profiles')
          .update({'community_id': _defaultCommunityId})
          .eq('id', widget.user['id']);

      // 2. Insert their role into the user_roles table
      await Supabase.instance.client.from('user_roles').upsert({
        'profile_id': widget.user['id'],
        'role_id': int.parse(_selectedRoleId!),
        'community_id': _defaultCommunityId,
        'is_active': true,
      });

      if (!mounted) return;
      Navigator.pop(context); 
      widget.onRoleAssigned(); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role assigned successfully!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning role: $e'), backgroundColor: const Color(0xFFD9534F)),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, 
                  decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Assign Role to ${widget.user['full_name']}', 
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a system role to grant this user access to the AEC platform.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              
              _isLoadingRoles 
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                : DropdownButtonFormField<String>(
                    initialValue: _selectedRoleId,
                    hint: const Text('Select Role'),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    items: _availableRoles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role['id'].toString(), 
                        child: Text(role['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedRoleId = val),
                  ),
              
              const SizedBox(height: 32),
              
              FilledButton(
                onPressed: _saving || _selectedRoleId == null ? null : _assignRole,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Assignment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}