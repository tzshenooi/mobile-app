import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_ui.dart';

/// Completed missions for this driver (Records tab).
class DriverRecordsTab extends StatefulWidget {
  const DriverRecordsTab({super.key, required this.driverId});

  final String driverId;

  @override
  State<DriverRecordsTab> createState() => _DriverRecordsTabState();
}

class _DriverRecordsTabState extends State<DriverRecordsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _client
          .from('bookings')
          .select(
            'id, patient_name, patient_id, location, status, emergency_type, '
            'discharge_completed_at, patient_picked_up_at, requested_at, created_at, notes',
          )
          .eq('driver_id', widget.driverId)
          .eq('status', 'Completed')
          .order('discharge_completed_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  DateTime? _parseTime(Map<String, dynamic> row) {
    final raw = row['discharge_completed_at'] ?? row['patient_picked_up_at'] ?? row['requested_at'] ?? row['created_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  void _openDetail(Map<String, dynamic> row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final when = _parseTime(row);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.paddingOf(ctx).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row['patient_name']?.toString() ?? 'Patient',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 12),
              _detailRow('Completed', DriverUi.formatWhen(when)),
              _detailRow('Patient ID', row['patient_id']?.toString() ?? '—'),
              _detailRow('Pickup', row['location']?.toString() ?? '—'),
              _detailRow('Priority', row['emergency_type']?.toString() ?? '—'),
              if ((row['notes'] ?? '').toString().trim().isNotEmpty)
                _detailRow('Notes', row['notes'].toString()),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: DriverUi.primaryBlue),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blueGrey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF334155)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabHeader(
            title: 'Mission records',
            subtitle: 'Completed dispatches',
            icon: Icons.description_outlined,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DriverUi.primaryBlue))
                : _error != null
                    ? _errorState()
                    : _rows.isEmpty
                        ? _emptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: DriverUi.primaryBlue,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final row = _rows[i];
                                final when = _parseTime(row);
                                return Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openDetail(row),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: DriverUi.primaryBlue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.check_circle_outline, color: DriverUi.primaryBlue),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  row['patient_name']?.toString() ?? 'Unknown',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: Color(0xFF1E293B),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  row['location']?.toString() ?? '—',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  DriverUi.formatWhen(when),
                                                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right, color: Colors.grey),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No completed missions yet',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            const Text(
              'Finished jobs appear here after you complete discharge.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _tabHeader({required String title, required String subtitle, required IconData icon}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [DriverUi.primaryBlue, DriverUi.darkBlue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ],
    ),
  );
}
