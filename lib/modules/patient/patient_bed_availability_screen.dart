import 'package:flutter/material.dart';

import 'patient_clinic_contact.dart';
import 'patient_ui.dart';

/// Bed counts from clinic (own sidebar in portal, not under Settings).
class PatientBedAvailabilityScreen extends StatefulWidget {
  const PatientBedAvailabilityScreen({super.key});

  @override
  State<PatientBedAvailabilityScreen> createState() => _PatientBedAvailabilityScreenState();
}

class _PatientBedAvailabilityScreenState extends State<PatientBedAvailabilityScreen> {
  PatientClinicContact? _contact;
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await PatientClinicContact.load();
      if (!mounted) return;
      setState(() {
        _contact = c;
        _loading = false;
        _error = c.showsBedAvailability ? null : 'Not set by clinic yet.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beds'),
        backgroundColor: PatientUi.accentRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                ),
              )
            else if (_contact != null && _contact!.showsBedAvailability)
              PatientBedAvailabilityCard(clinic: _contact!),
          ],
        ),
      ),
    );
  }
}

class PatientBedAvailabilityCard extends StatelessWidget {
  const PatientBedAvailabilityCard({super.key, required this.clinic});

  final PatientClinicContact clinic;

  static const Color _freeGreen = Color(0xFF0D9488);

  @override
  Widget build(BuildContext context) {
    final free = clinic.bedsAvailable;
    final freeColor = free > 0 ? _freeGreen : Colors.grey.shade600;

    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: PatientUi.accentRed),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _BedStatColumn(
                          label: 'Free',
                          value: '$free',
                          valueColor: freeColor,
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.grey.shade200),
                      Expanded(
                        child: _BedStatColumn(
                          label: 'Used',
                          value: '${clinic.bedsOccupied}',
                          valueColor: Colors.black87,
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.grey.shade200),
                      Expanded(
                        child: _BedStatColumn(
                          label: 'Total',
                          value: '${clinic.bedCapacity}',
                          valueColor: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BedStatColumn extends StatelessWidget {
  const _BedStatColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: valueColor,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
