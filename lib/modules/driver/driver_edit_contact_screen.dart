import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_contact_service.dart';
import 'driver_ui.dart';

class DriverEditContactScreen extends StatefulWidget {
  const DriverEditContactScreen({
    super.key,
    required this.driverId,
    this.initialPhone,
    this.initialIc,
  });

  final String driverId;
  final String? initialPhone;
  final String? initialIc;

  @override
  State<DriverEditContactScreen> createState() => _DriverEditContactScreenState();
}

class _DriverEditContactScreenState extends State<DriverEditContactScreen> {
  final _client = Supabase.instance.client;
  final _phone = TextEditingController();
  final _ic = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phone.text = widget.initialPhone ?? '';
    _ic.text = widget.initialIc ?? '';
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _ic.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contact = await DriverContactService.load(_client, widget.driverId);
      if (!mounted || contact == null) return;
      setState(() {
        if (_phone.text.isEmpty && contact.phoneNumber?.isNotEmpty == true) {
          _phone.text = contact.phoneNumber!;
        }
        if (_ic.text.isEmpty && contact.icNumber?.isNotEmpty == true) {
          _ic.text = contact.icNumber!;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    final ic = _ic.text.trim();

    if (phone.isEmpty && ic.isEmpty) {
      _showMessage('Enter at least a phone number or IC number.');
      return;
    }

    setState(() => _saving = true);
    try {
      await DriverContactService.save(
        client: _client,
        phoneNumber: phone.isEmpty ? null : phone,
        icNumber: ic.isEmpty ? null : ic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact details saved.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        '$e\nIf this mentions a missing function, run driver_update_contact.sql in Supabase.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverUi.bgGray,
      appBar: AppBar(
        title: const Text('Contact details'),
        backgroundColor: DriverUi.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DriverUi.primaryBlue))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  'Add your phone and IC number so your clinic can reach you and verify your identity.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    hintText: 'e.g. 012-345 6789',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _ic,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'IC number',
                    hintText: 'e.g. 900101-01-1234',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriverUi.primaryBlue,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        )
                      : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }
}
