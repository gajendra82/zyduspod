import 'package:flutter/material.dart';
import 'package:zyduspod/Models/notification_model.dart';
import 'package:zyduspod/services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService();
  final ScrollController _scrollController = ScrollController();
  final List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final response = await _service.fetchNotifications(page: 1);
      setState(() {
        _notifications
          ..clear()
          ..addAll(response.notifications);
        _page = response.currentPage;
        // Stop pagination if:
        // 1. No notifications returned
        // 2. No next page available
        // 3. Reached last page (if available)
        _hasMore = response.notifications.isNotEmpty && 
                   response.hasNextPage &&
                   (response.lastPage == null || response.currentPage < response.lastPage!);
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    // Don't load more if already loading, no more pages, or reached last page
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _service.fetchNotifications(page: nextPage);
      
      setState(() {
        // Only add notifications if we got some
        if (response.notifications.isNotEmpty) {
          _notifications.addAll(response.notifications);
          _page = response.currentPage;
        }
        
        // Stop pagination if:
        // 1. No notifications returned (empty page)
        // 2. No next page available
        // 3. Reached last page (if available)
        _hasMore = response.notifications.isNotEmpty && 
                   response.hasNextPage &&
                   (response.lastPage == null || response.currentPage < response.lastPage!);
      });
    } catch (e) {
      print('Error loading more notifications: $e');
      // On error, stop pagination to prevent infinite retries
      setState(() {
        _hasMore = false;
      });
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
        ),
      );
    }
    if (_hasError) {
      return _buildError();
    }
    if (_notifications.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF00A0A8),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          if (index == _notifications.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            // Show "no more items" message if we've reached the end
            if (!_hasMore && _notifications.isNotEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No more notifications',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final n = _notifications[index];
          return _NotificationCard(notification: n);
        },
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemCount: _notifications.length + 1,
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_off_rounded,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'No notifications yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'You will see updates and alerts here',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text('Failed to load notifications', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_errorMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final Color color = notification.statusColor();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(notification.statusIcon(), color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C3E50),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (notification.createdAt != null)
                            Text(
                              _formatRelative(notification.createdAt!),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (notification.description != null && notification.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  notification.description!,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  notification.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}


