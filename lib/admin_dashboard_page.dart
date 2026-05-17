import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pending_verifications_page.dart';
import 'admin_users_page.dart';
import 'admin_volunteers_page.dart';

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
      backgroundColor: Colors.grey.shade100,
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
      color: Colors.white,
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'BlindFriend',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          const SizedBox(height: 8),

          _navItem(icon: Icons.dashboard_outlined, label: 'Overview', pageKey: 'overview'),
          _navItem(icon: Icons.people_outline, label: 'Volunteers', pageKey: 'volunteers'),
          _navItem(icon: Icons.verified_user_outlined, label: 'Verification', pageKey: 'verification'),
          _navItem(icon: Icons.person_outline, label: 'Users', pageKey: 'users'),

          const Spacer(),
          const Divider(height: 1),

          // Logged in user
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logged in as',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(
                  admin?.email ?? 'Admin',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _logout(context),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text('Logout',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
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

  Widget _navItem({required IconData icon, required String label, required String pageKey}) {
    final isActive = _activePage == pageKey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, size: 18,
            color: isActive ? Colors.deepPurple : Colors.grey.shade700),
        title: Text(label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? Colors.deepPurple : Colors.grey.shade800,
            )),
        tileColor: isActive ? Colors.deepPurple.shade50 : Colors.transparent,
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
        return _buildOverviewPage();
      case 'verification':
        return const PendingVerificationsPage();
      case 'volunteers':
        return const AdminVolunteersPage();
      case 'users':
        return const AdminUsersPage();
      default:
        return _buildOverviewPage();
    }
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW PAGE
  // ---------------------------------------------------------------------------

  Widget _buildOverviewPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overview',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Welcome to the BlindFriend Admin Portal',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
          const SizedBox(height: 28),
          _buildStatCards(),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    return FutureBuilder<Map<String, int>>(
      future: _fetchStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {'volunteers': 0, 'verified': 0, 'blindUsers': 0};

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _statCard(
              icon: Icons.volunteer_activism,
              iconColor: Colors.blue,
              label: 'Total Volunteers',
              value: '${stats['volunteers']}',
            ),
            _statCard(
              icon: Icons.verified,
              iconColor: Colors.green,
              label: 'Verified Volunteers',
              value: '${stats['verified']}',
            ),
            _statCard(
              icon: Icons.accessibility_new,
              iconColor: Colors.orange,
              label: 'Blind Users',
              value: '${stats['blindUsers']}',
            ),
            _statCard(
              icon: Icons.flag_outlined,
              iconColor: Colors.red,
              label: 'Reports Made',
              value: '0',
            ),
          ],
        );
      },
    );
  }

  // Fetches counts from Firestore in one go
  Future<Map<String, int>> _fetchStats() async {
    final firestore = FirebaseFirestore.instance;

    final volunteersSnap = await firestore.collection('volunteers').get();
    final verifiedSnap = await firestore
        .collection('volunteers')
        .where('status', isEqualTo: 'approved')
        .get();
    final blindUsersSnap = await firestore
        .collection('users')
        .where('userType', isEqualTo: 'blind')
        .get();

    return {
      'volunteers': volunteersSnap.docs.length,
      'verified': verifiedSnap.docs.length,
      'blindUsers': blindUsersSnap.docs.length,
    };
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}