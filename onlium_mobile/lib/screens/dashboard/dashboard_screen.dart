import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../dashboard/appointment_screen.dart';
import '../enrollment/enrollment_screen.dart';
import '../notifications/notification_screen.dart';
import '../resources/resource_screen.dart';
import '../study_load/study_load_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _refreshTimer;

  bool _isLoadingSummary = true;
  String? _summaryError;

  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _applications = [];
  List<Map<String, dynamic>> _bulletins = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardSummary();
    });

    // Auto-refresh every 8 seconds while the user is on Home.
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;

      if (_currentIndex == 0 && !_isLoadingSummary) {
        _loadDashboardSummary(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && _currentIndex == 0) {
      _loadDashboardSummary(showLoading: false);
    }
  }

  Future<String?> _waitForToken() async {
    for (int i = 0; i < 15; i++) {
      if (!mounted) return null;

      final token = context.read<AuthProvider>().token;

      if (token != null && token.isNotEmpty) {
        return token;
      }

      await Future.delayed(const Duration(milliseconds: 200));
    }

    return null;
  }

  Future<http.Response?> _safeGet(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 8));

      debugPrint('Dashboard GET: $url');
      debugPrint('Dashboard status: ${response.statusCode}');
      debugPrint('Dashboard body: ${response.body}');

      return response;
    } catch (e) {
      debugPrint('Dashboard request failed: $url');
      debugPrint('Dashboard error: $e');
      return null;
    }
  }

  Future<void> _loadDashboardSummary({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() {
        _isLoadingSummary = true;
        _summaryError = null;
      });
    }

    try {
      final token = await _waitForToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _summaryError = 'Your session is still loading. Please refresh.';
          _isLoadingSummary = false;
        });
        return;
      }

      final headers = {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final notificationsResponse = await _safeGet(
        '${ApiConfig.baseUrl}/api/Notifications/mine',
        headers,
      );

      final appointmentsResponse = await _safeGet(
        '${ApiConfig.baseUrl}/api/Appointments/mine',
        headers,
      );

      final applicationsResponse = await _safeGet(
        '${ApiConfig.baseUrl}/api/Applications/mine',
        headers,
      );

      final bulletinsResponse = await _safeGet(
        '${ApiConfig.baseUrl}/api/Bulletins',
        headers,
      );

      List<Map<String, dynamic>> notifications = [];
      List<Map<String, dynamic>> appointments = [];
      List<Map<String, dynamic>> applications = [];
      List<Map<String, dynamic>> bulletins = [];
      final errors = <String>[];

      if (notificationsResponse?.statusCode == 200) {
        notifications = _decodeList(notificationsResponse!.body);
      } else {
        errors.add('Notifications unavailable');
      }

      if (appointmentsResponse?.statusCode == 200) {
        appointments = _decodeList(appointmentsResponse!.body);
      } else {
        errors.add('Appointments unavailable');
      }

      if (applicationsResponse?.statusCode == 200) {
        applications = _decodeList(applicationsResponse!.body);
      } else {
        errors.add('Applications unavailable');
      }

      if (bulletinsResponse?.statusCode == 200) {
        bulletins = _decodeList(bulletinsResponse!.body);
      } else {
        errors.add('Bulletins unavailable');
      }

      _sortByNewest(notifications, 'createdAt');
      _sortByNewest(appointments, 'appointmentDate');
      _sortApplicationsByNewest(applications);
      _sortByNewest(bulletins, 'createdAt');

      if (!mounted) return;

      setState(() {
        _notifications = notifications;
        _appointments = appointments;
        _applications = applications;
        _bulletins = bulletins;
        _summaryError = errors.length == 4 ? errors.join(' • ') : null;
        _isLoadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _summaryError = 'Error loading dashboard: $e';
        _isLoadingSummary = false;
      });
    }
  }

  List<Map<String, dynamic>> _decodeList(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! List) {
        return [];
      }

      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Dashboard decode error: $e');
      return [];
    }
  }

  void _sortByNewest(List<Map<String, dynamic>> items, String dateKey) {
    items.sort((a, b) {
      final aDate =
          DateTime.tryParse(a[dateKey]?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(b[dateKey]?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return bDate.compareTo(aDate);
    });
  }

  void _sortApplicationsByNewest(List<Map<String, dynamic>> items) {
    items.sort((a, b) {
      final aDate =
          DateTime.tryParse(
            a['submittedAt']?.toString() ?? a['createdAt']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final bDate =
          DateTime.tryParse(
            b['submittedAt']?.toString() ?? b['createdAt']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return bDate.compareTo(aDate);
    });
  }

  int get _unreadNotificationCount =>
      _notifications.where((e) => e['isRead'] != true).length;

  Map<String, dynamic>? get _latestAppointment =>
      _appointments.isNotEmpty ? _appointments.first : null;

  Map<String, dynamic>? get _latestApplication =>
      _applications.isNotEmpty ? _applications.first : null;

  Map<String, dynamic>? get _latestBulletin =>
      _bulletins.isNotEmpty ? _bulletins.first : null;

  String get _latestApplicationStatus =>
      _latestApplication?['status']?.toString().trim() ?? '';

  String get _latestAppointmentStatus =>
      _latestAppointment?['status']?.toString().trim() ?? '';

  bool get _hasCompletedAppointment =>
      _latestAppointmentStatus.toLowerCase() == 'completed';

  bool get _hasCompletedApplication {
    final status = _latestApplicationStatus.toLowerCase();

    return status == 'approved' ||
        status == 'completed' ||
        status == 'enrolled';
  }

  bool get _isEnrolled => _hasCompletedAppointment || _hasCompletedApplication;

  String get _studentStatusText {
    if (_isLoadingSummary) return 'Checking...';

    final appStatus = _latestApplicationStatus.toLowerCase();
    final appointmentStatus = _latestAppointmentStatus.toLowerCase();

    if (_isEnrolled) return 'Enrolled';

    if (appointmentStatus == 'scheduled') return 'For Appointment';

    if (appointmentStatus == 'paymentconfirmed' ||
        appointmentStatus == 'payment confirmed') {
      return 'Payment Confirmed';
    }

    if (appStatus == 'pendingreview' || appStatus == 'pending review') {
      return 'Pending Review';
    }

    if (appStatus == 'rejected') return 'Rejected';
    if (appStatus == 'draft') return 'Draft';

    return 'Not Enrolled';
  }

  String get _enrollmentProgressText {
    if (_isLoadingSummary) return 'Loading enrollment status...';

    final appStatus = _latestApplicationStatus.toLowerCase();
    final appointmentStatus = _latestAppointmentStatus.toLowerCase();

    if (appointmentStatus == 'completed' ||
        appStatus == 'approved' ||
        appStatus == 'completed' ||
        appStatus == 'enrolled') {
      return 'Enrollment Completed';
    }

    if (appointmentStatus == 'scheduled') {
      return 'Appointment Scheduled';
    }

    if (appointmentStatus == 'paymentconfirmed' ||
        appointmentStatus == 'payment confirmed') {
      return 'Payment Confirmed';
    }

    if (_latestApplicationStatus.isNotEmpty) {
      return _friendlyApplicationStatus(_latestApplicationStatus);
    }

    return 'No Enrollment Yet';
  }

  Color get _studentStatusColor {
    if (_isLoadingSummary) return Colors.blueGrey;

    final status = _studentStatusText.toLowerCase();

    if (status == 'enrolled' ||
        status == 'approved' ||
        status == 'payment confirmed') {
      return Colors.green;
    }

    if (status == 'pending review' ||
        status == 'for appointment' ||
        status == 'draft') {
      return Colors.orange;
    }

    if (status == 'rejected') {
      return Colors.red;
    }

    return Colors.orange;
  }

  String _friendlyApplicationStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'pendingreview':
      case 'pending review':
        return 'Pending Review';
      case 'approved':
        return 'Application Approved';
      case 'rejected':
        return 'Application Rejected';
      case 'paymentrequired':
      case 'payment required':
        return 'Payment Required';
      case 'completed':
      case 'enrolled':
        return 'Enrollment Completed';
      default:
        return status == null || status.isEmpty ? 'No Enrollment Yet' : status;
    }
  }

  String _friendlyAppointmentStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'scheduled':
        return 'Appointment Scheduled';
      case 'paymentconfirmed':
      case 'payment confirmed':
        return 'Payment Confirmed';
      case 'completed':
        return 'Enrollment Completed';
      case 'cancelled':
        return 'Appointment Cancelled';
      default:
        return status == null || status.isEmpty ? 'No Appointment Yet' : status;
    }
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'scheduled':
        return 'Appointment Scheduled';
      case 'paymentconfirmed':
      case 'payment confirmed':
        return 'Payment Confirmed';
      case 'completed':
        return 'Enrollment Completed';
      case 'cancelled':
        return 'Appointment Cancelled';
      default:
        return status;
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';

    final raw = value.toString();
    final parsed = DateTime.tryParse(raw);

    if (parsed == null) return raw;

    final hour = parsed.hour == 0
        ? 12
        : parsed.hour > 12
        ? parsed.hour - 12
        : parsed.hour;

    final minute = parsed.minute.toString().padLeft(2, '0');
    final period = parsed.hour >= 12 ? 'PM' : 'AM';

    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
        '$hour:$minute $period';
  }

  String _shortenText(String text, {int maxLength = 120}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  IconData _notificationTypeIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'application':
      case 'approval':
      case 'enrollment':
        return Icons.school;
      case 'rejection':
        return Icons.cancel;
      case 'appointment':
        return Icons.event;
      case 'payment':
        return Icons.payments;
      case 'bulletin':
        return Icons.campaign;
      case 'lms':
      case 'resource':
        return Icons.link;
      case 'studyload':
      case 'study load':
        return Icons.fact_check;
      default:
        return Icons.notifications;
    }
  }

  Color _notificationTypeColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'application':
      case 'approval':
      case 'enrollment':
        return Colors.green;
      case 'rejection':
        return Colors.red;
      case 'appointment':
        return Colors.orange;
      case 'payment':
        return Colors.blue;
      case 'bulletin':
        return Colors.indigo;
      case 'lms':
      case 'resource':
        return Colors.purple;
      case 'studyload':
      case 'study load':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  List<_RecentActivityItem> _buildRecentActivities() {
    final items = <_RecentActivityItem>[];

    if (_isLoadingSummary) {
      return const [
        _RecentActivityItem(
          title: 'Checking enrollment status',
          subtitle:
              'Loading your latest enrollment, appointment, and notification data.',
          trailingText: 'Please wait',
          icon: Icons.sync,
          iconColor: Colors.blueGrey,
        ),
      ];
    }

    if (_latestApplication != null) {
      final status = _latestApplication!['status']?.toString() ?? '';

      items.add(
        _RecentActivityItem(
          title: 'Enrollment Status',
          subtitle: _friendlyApplicationStatus(status),
          trailingText: _formatDate(
            _latestApplication!['submittedAt'] ??
                _latestApplication!['createdAt'],
          ),
          icon: _isEnrolled ? Icons.school : Icons.assignment,
          iconColor: _isEnrolled ? Colors.green : Colors.blue,
        ),
      );
    }

    if (_latestAppointment != null) {
      final status = _latestAppointment!['status']?.toString() ?? 'Scheduled';
      final normalizedStatus = status.toLowerCase();

      items.add(
        _RecentActivityItem(
          title: _statusLabel(status),
          subtitle:
              'Appointment on ${_formatDate(_latestAppointment!['appointmentDate'])}',
          trailingText:
              _latestAppointment!['location']?.toString() ?? 'School Campus',
          icon: Icons.event_available,
          iconColor: normalizedStatus == 'completed'
              ? Colors.green
              : normalizedStatus == 'paymentconfirmed' ||
                    normalizedStatus == 'payment confirmed'
              ? Colors.blue
              : Colors.orange,
        ),
      );
    }

    if (_latestBulletin != null) {
      items.add(
        _RecentActivityItem(
          title: _latestBulletin!['title']?.toString() ?? 'Bulletin',
          subtitle: _shortenText(
            _latestBulletin!['content']?.toString() ?? '',
            maxLength: 80,
          ),
          trailingText: _formatDate(_latestBulletin!['createdAt']),
          icon: Icons.campaign,
          iconColor: Colors.indigo,
        ),
      );
    }

    for (final notification in _notifications.take(2)) {
      final type = notification['notificationType']?.toString() ?? 'General';

      items.add(
        _RecentActivityItem(
          title: notification['title']?.toString() ?? 'Notification',
          subtitle: notification['message']?.toString() ?? '',
          trailingText: _formatDate(notification['createdAt']),
          icon: _notificationTypeIcon(type),
          iconColor: _notificationTypeColor(type),
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const _RecentActivityItem(
          title: 'Logged in successfully',
          subtitle: 'Your student dashboard is ready to use.',
          trailingText: 'Just now',
          icon: Icons.login,
          iconColor: Colors.green,
        ),
      );
    }

    return items;
  }

  void _showBulletinsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: double.maxFinite,
          height: 520,
          child: Column(
            children: [
              AppBar(
                title: const Text('Bulletin Board'),
                automaticallyImplyLeading: false,
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: _bulletins.isEmpty
                    ? const Center(
                        child: Text(
                          'No bulletins available yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _bulletins.length,
                        itemBuilder: (context, index) {
                          final bulletin = _bulletins[index];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bulletin['title']?.toString() ?? 'Untitled',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    bulletin['content']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Posted: ${_formatDate(bulletin['createdAt'])}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(
            key: ValueKey(
              '${_isLoadingSummary}_${_latestAppointmentStatus}_${_latestApplicationStatus}_${_unreadNotificationCount}',
            ),
            parentState: this,
          ),
          const EnrollmentScreen(),
          const StudyLoadScreen(),
          const ResourceScreen(),
          const AppointmentScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);

              if (index == 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _loadDashboardSummary(showLoading: false);
                });
              }
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: const Color(0xFF1E63B6),
            unselectedItemColor: Colors.grey[500],
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 10),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment_outlined),
                activeIcon: Icon(Icons.assignment),
                label: 'Enrollment',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.school_outlined),
                activeIcon: Icon(Icons.school),
                label: 'Study Load',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.article_outlined),
                activeIcon: Icon(Icons.article),
                label: 'Resources',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today_outlined),
                activeIcon: Icon(Icons.calendar_today),
                label: 'Appointments',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AuthProvider authProvider) {
    return Row(
      children: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.menu, color: Colors.white),
          color: Colors.white,
          onSelected: (value) async {
            if (value == 'edit_profile') {
              _showEditProfileDialog(context, authProvider);
            } else if (value == 'logout') {
              await authProvider.logout();

              if (!context.mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem(
              value: 'edit_profile',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Color(0xFF1E63B6)),
                  SizedBox(width: 12),
                  Text('Edit Profile'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Log Out', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          child: Icon(Icons.school, color: Color(0xFF1E4A8A), size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  void _showEditProfileDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: const Text('Edit profile functionality coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountHeader(AuthProvider authProvider) {
    final fullName = authProvider.fullName?.isNotEmpty == true
        ? authProvider.fullName!
        : 'Student';

    final statusColor = _studentStatusColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF1E63B6).withOpacity(0.12),
            child: const Icon(Icons.person, color: Color(0xFF1E63B6), size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E4A8A),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Student Status: ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _studentStatusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enrollment Progress: $_enrollmentProgressText',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  authProvider.email ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBanner(BuildContext context) {
    final bannerText = _isLoadingSummary
        ? 'Loading your latest updates...'
        : _unreadNotificationCount > 0
        ? 'You have $_unreadNotificationCount new notification${_unreadNotificationCount == 1 ? '' : 's'} including enrollment updates and important announcements.'
        : 'You have no new notifications right now.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E9D8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bannerText,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Color(0xFFB36A19),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                );

                if (!mounted) return;
                _loadDashboardSummary(showLoading: false);
              },
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward, color: Color(0xFFB36A19)),
              label: const Text(
                'View All',
                style: TextStyle(
                  color: Color(0xFFB36A19),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletinCard() {
    final latestTitle = _latestBulletin?['title']?.toString();
    final latestContent = _latestBulletin?['content']?.toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign, color: Color(0xFF2A68B8), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Bulletin Board',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2A68B8),
                        ),
                      ),
                    ),
                    if (_latestBulletin != null) const _NewBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                if (_isLoadingSummary)
                  const Text(
                    'Loading latest bulletin...',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF2A68B8),
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (_latestBulletin == null)
                  const Text(
                    'No bulletin announcements available yet.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF2A68B8),
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else ...[
                  Text(
                    latestTitle ?? 'Latest Bulletin',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2A68B8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _shortenText(latestContent ?? '', maxLength: 160),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Color(0xFF2A68B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _showBulletinsDialog,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(
                        Icons.arrow_forward,
                        color: Color(0xFF2A68B8),
                      ),
                      label: const Text(
                        'View All',
                        style: TextStyle(
                          color: Color(0xFF2A68B8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_summaryError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _summaryError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard(List<_RecentActivityItem> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: item.iconColor.withOpacity(0.12),
                    child: Icon(item.icon, color: item.iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.trailingText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (index != items.length - 1) ...[
                const SizedBox(height: 14),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 14),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE64A4A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final _DashboardScreenState parentState;

  const _HomeTab({super.key, required this.parentState});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  @override
  Widget build(BuildContext context) {
    final parent = widget.parentState;
    final authProvider = context.watch<AuthProvider>();
    final recentActivities = parent._buildRecentActivities();

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E63B6),
            Color(0xFF5F97D8),
            Color(0xFF9CC8F5),
            Color(0xFFD6ECFF),
          ],
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: parent._loadDashboardSummary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              parent._buildTopBar(context, authProvider),
              const SizedBox(height: 14),
              parent._buildAccountHeader(authProvider),
              const SizedBox(height: 14),
              parent._buildNotificationBanner(context),
              const SizedBox(height: 14),
              parent._buildBulletinCard(),
              const SizedBox(height: 24),
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              parent._buildRecentActivityCard(recentActivities),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityItem {
  final String title;
  final String subtitle;
  final String trailingText;
  final IconData icon;
  final Color iconColor;

  const _RecentActivityItem({
    required this.title,
    required this.subtitle,
    required this.trailingText,
    required this.icon,
    required this.iconColor,
  });
}
