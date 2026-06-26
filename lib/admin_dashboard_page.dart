import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pending_verifications_page.dart';
import 'admin_users_page.dart';
import 'admin_volunteers_page.dart';
import 'admin_overview_page.dart';
import 'admin_reports_page.dart';
import 'theme/app_palette.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  String _activePage = 'overview';

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildCurrentPage()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SIDEBAR
  // ---------------------------------------------------------------------------

  Widget _buildSidebar() {
    final admin = FirebaseAuth.instance.currentUser;

    return Container(
      width: 220,
      color: kNavyMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Portal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'BlindFriend',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 8),

          _navItem(
              icon: Icons.dashboard_outlined,
              label: 'Overview',
              pageKey: 'overview'),
          _navItem(
              icon: Icons.people_outline,
              label: 'Volunteers',
              pageKey: 'volunteers'),
          _navItem(
              icon: Icons.verified_user_outlined,
              label: 'Verification',
              pageKey: 'verification'),
          _navItem(
              icon: Icons.person_outline, label: 'Users', pageKey: 'users'),
          _navItem(
              icon: Icons.flag_outlined,
              label: 'Reports',
              pageKey: 'reports'),

          const Spacer(),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

          // Logged in user
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Logged in as',
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
                const SizedBox(height: 2),
                Text(
                  admin?.email ?? 'Admin',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _logout(context),
                  child: const Row(
                    children: [
                      Icon(Icons.logout, size: 16, color: kRedAccent),
                      SizedBox(width: 6),
                      Text('Logout',
                          style: TextStyle(fontSize: 14, color: kRedAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
      {required IconData icon,
      required String label,
      required String pageKey}) {
    final isActive = _activePage == pageKey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon,
            size: 18, color: isActive ? kPinkBright : Colors.white60),
        title: Text(label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? kPinkBright : Colors.white70,
            )),
        tileColor:
            isActive ? kPinkBright.withValues(alpha: 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        dense: true,
        onTap: () => setState(() => _activePage = pageKey),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAGE SWITCHER
  // ---------------------------------------------------------------------------

  Widget _buildCurrentPage() {
    switch (_activePage) {
      case 'overview':
        return AdminOverviewPage(
          onNavigate: (pageKey) => setState(() => _activePage = pageKey),
        );
      case 'verification':
        return const PendingVerificationsPage();
      case 'volunteers':
        return const AdminVolunteersPage();
      case 'users':
        return const AdminUsersPage();
      case 'reports':
        return const AdminReportsPage();
      default:
        return AdminOverviewPage(
          onNavigate: (pageKey) => setState(() => _activePage = pageKey),
        );
    }
  }
}
