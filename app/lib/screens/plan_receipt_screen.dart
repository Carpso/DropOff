import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data/dropoff_api.dart';
import '../ui/app_spinner.dart';
import '../ui/app_toast.dart';

class PlanReceiptScreen extends StatefulWidget {
  const PlanReceiptScreen({super.key, required this.paymentId});
  final String paymentId;

  @override
  State<PlanReceiptScreen> createState() => _PlanReceiptScreenState();
}

class _PlanReceiptScreenState extends State<PlanReceiptScreen> {
  final _boundaryKey = GlobalKey();
  bool _loading = true;
  bool _sharing = false;
  Map<String, dynamic>? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await DropOffApi.paymentReceipt(widget.paymentId);
    if (!mounted) return;
    setState(() {
      _receipt = r;
      _loading = false;
      _error = r == null
          ? 'Your payment is safe. We could not open the receipt right now. Check your connection and tap Retry; if you just paid, allow a moment for confirmation.'
          : null;
    });
  }

  Future<void> _share() async {
    if (_sharing || _receipt == null) return;
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('receipt_not_ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('encode_failed');
      final bytes = byteData.buffer.asUint8List();
      final no = (_receipt?['receipt_no'] ?? 'receipt').toString();
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: '$no.png')],
        subject: 'DropOff receipt $no',
      );
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not share receipt — please try again.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F3),
      appBar: AppBar(
        title: const Text('Payment receipt', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Download / share receipt',
            onPressed: _sharing ? null : _share,
            icon: _sharing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: AppLogoSpinner())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ])))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  RepaintBoundary(key: _boundaryKey, child: _ReceiptCard(receipt: _receipt!)),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(_sharing ? 'Preparing...' : 'Download / share receipt'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Keep this receipt for your records. DropOff can verify it using the receipt number and payment reference.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF5F6B66), height: 1.4)),
                ]),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});
  final Map<String, dynamic> receipt;

  String _s(dynamic v) => v == null ? '' : v.toString();
  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return 'K${n.toStringAsFixed(2)}';
  }
  String _date(dynamic v) {
    final raw = _s(v).trim();
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw.endsWith('Z') ? raw : '${raw}Z');
    if (dt == null) return raw;
    final cat = dt.toUtc().add(const Duration(hours: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${two(cat.day)} ${months[cat.month - 1]} ${cat.year}, ${two(cat.hour)}:${two(cat.minute)} CAT';
  }

  @override
  Widget build(BuildContext context) {
    final amounts = (receipt['amounts'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final plan = (receipt['plan'] as Map?)?.cast<String, dynamic>();
    final business = (receipt['business'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final status = _s(receipt['status']).toLowerCase();
    final isSuccess = status == 'success';
    final statusColor = isSuccess ? const Color(0xFF1E7A43) : status == 'pending' ? const Color(0xFFB45309) : const Color(0xFFB3261E);
    final statusLabel = isSuccess ? 'PAID' : status == 'pending' ? 'PENDING' : status.toUpperCase();
    final kind = _s(receipt['kind']);
    final isPlan = kind == 'subscription' || kind == 'upgrade';
    final title = switch (kind) {
      'subscription' => 'Plan payment receipt',
      'upgrade' => 'Plan upgrade receipt',
      'counter_fare' => 'Counter fare receipt',
      'booking_deposit' => 'Booking deposit receipt',
      'job' => 'Delivery payment receipt',
      'topup' => 'Wallet top-up receipt',
      'cod_remit' => 'COD remittance receipt',
      'rider_reimbursement' => 'Rider reimbursement receipt',
      'refund' => 'Refund receipt',
      _ => 'Payment receipt',
    };

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))]),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/brand/dropoff_logo.png', width: 52, height: 52, fit: BoxFit.cover)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DropOff', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF143B2B))),
              Text(_s(business['legal']).isEmpty ? 'by Carpso Solutions' : _s(business['legal']), style: const TextStyle(fontSize: 12, color: Color(0xFF5F6B66))),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2A2A2A))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _row('Receipt no', _s(receipt['receipt_no'])),
          _row('Date', _date(receipt['paid_at'] ?? receipt['created_at'])),
          _row('Buyer', _s(receipt['buyer_name']).isEmpty ? _s(receipt['phone']) : _s(receipt['buyer_name'])),
          _row('Phone', _s(receipt['phone'])),
          if (isPlan && plan != null) ...[
            _row('Plan', _s(plan['name']).isEmpty ? _s(plan['tier']).toUpperCase() : _s(plan['name'])),
            if (_s(plan['period_start']).isNotEmpty || _s(plan['period_end']).isNotEmpty)
              _row('Period', '${_date(plan['period_start'])}  →  ${_date(plan['period_end'])}'),
          ],
          if (_s(receipt['job_ref']).isNotEmpty) _row('Reference', _s(receipt['job_ref'])),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (isPlan) _row('Plan amount', _money(amounts['plan_amount_zmw'] ?? amounts['credit_zmw'])),
          if (!isPlan && _s(receipt['kind']) == 'counter_fare') _row('Depot receipt amount', _money(amounts['receipt_amount_zmw'])),
          _row('Processing fee', _money(amounts['processing_fee_zmw'])),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF4F8F4), borderRadius: BorderRadius.circular(12)),
            child: _row('Total paid', _money(amounts['total_zmw']), bold: true, valueColor: const Color(0xFF143B2B)),
          ),
          const SizedBox(height: 14),
          _row('Payment ref', _s(receipt['gateway_reference']).isEmpty ? _s(receipt['lipila_reference']) : _s(receipt['gateway_reference'])),
          _row('Gateway', _s(receipt['gateway']).isEmpty ? '—' : _s(receipt['gateway']).toUpperCase()),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('DropOff by Carpso Solutions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
          const SizedBox(height: 2),
          Text('Contact: ${_s(business['phone']).isEmpty ? '0968551110' : _s(business['phone'])}  •  ${_s(business['email']).isEmpty ? 'support@carpsosolutions.store' : _s(business['email'])}',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF5F6B66), height: 1.4)),
          const SizedBox(height: 4),
          const Text('This receipt is computer-generated for audit and record keeping.',
              style: TextStyle(fontSize: 11, color: Color(0xFF7A8580), height: 1.35)),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 132, child: Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F6B66)))),
        Expanded(child: Text(value.isEmpty ? '—' : value, textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12.8, fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: valueColor ?? const Color(0xFF1C2521)))),
      ]),
    );
  }
}
