import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pending_verifications_page.dart';
import 'admin_users_page.dart';
import 'admin_volunteers_page.dart';
import 'admin_overview_page.dart';
import 'admin_reports_page.dart';
import 'theme/app_palette.dart';

// Below this width the permanent sidebar doesn't fit comfortably alongside
// page content, so a Drawer + AppBar take over instead.
const double _kWideBreakpoint = 800;

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

  String _pageTitle(String pageKey) {
    switch (pageKey) {
      case 'overview':
        return 'Overview';
      case 'volunteers':
        return 'Volunteers';
      case 'verification':
        return 'Verification';
      case 'users':
        return 'Users';
      case 'reports':
        return 'Reports';
      default:
        return 'Admin Portal';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kWideBreakpoint;

        if (isWide) {
          return Scaffold(
            backgroundColor: kNavyDeep,
            body: Row(
              children: [
                Container(
                  width: 220,
                  color: kNavyMid,
                  child: _buildSidebarContent(closeDrawerOnTap: false),
                ),
                Expanded(child: _buildCurrentPage()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: kNavyDeep,
          appBar: AppBar(
            backgroundColor: kNavyMid,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              _pageTitle(_activePage),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          drawer: Drawer(
            backgroundColor: kNavyMid,
            child: SafeArea(
              child: _buildSidebarContent(closeDrawerOnTap: true),
            ),
          ),
          body: _buildCurrentPage(),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SIDEBAR / DRAWER CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildSidebarContent({required bool closeDrawerOnTap}) {
    final admin = FirebaseAuth.instance.currentUser;

    return Column(
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
            pageKey: 'overview',
            closeDrawerOnTap: closeDrawerOnTap),
        _navItem(
            icon: Icons.people_outline,
            label: 'Volunteers',
            pageKey: 'volunteers',
            closeDrawerOnTap: closeDrawerOnTap),
        _navItem(
            icon: Icons.verified_user_outlined,
            label: 'Verification',
            pageKey: 'verification',
            closeDrawerOnTap: closeDrawerOnTap),
        _navItem(
            icon: Icons.person_outline,
            label: 'Users',
            pageKey: 'users',
            closeDrawerOnTap: closeDrawerOnTap),
        _navItem(
            icon: Icons.flag_outlined,
            label: 'Reports',
            pageKey: 'reports',
            closeDrawerOnTap: closeDrawerOnTap),

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
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required String pageKey,
    required bool closeDrawerOnTap,
  }) {
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
        onTap: () {
          setState(() => _activePage = pageKey);
          if (closeDrawerOnTap) Navigator.of(context).pop();
        },
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
