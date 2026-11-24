// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_toast.dart';
import 'app_theme.dart';

/// Portable Bluetooth thermal-printer waybill (ESC/POS).
///
/// Targets the cheap 58 mm portable receipt printers couriers and riders
/// actually carry (classic Bluetooth SPP — Xprinter/MTP-style). The receipt is
/// built as native ESC/POS text + CODE128 barcode, so it prints crisp and fast
/// — no bitmap rasterising, no image driver quirks. Bluetooth-only: iOS (BLE)
/// printers are not supported yet; the print button hides on non-Android.
class ThermalWaybill {
  ThermalWaybill._();

  /// Show the paired-device picker and print. Returns true when sent.
  static Future<bool> print(BuildContext context, WaybillPrintData data) async {
    // Runtime permission (Android 12+ needs BLUETOOTH_CONNECT to even list
    // bonded devices; older Android has it at install).
    var status = await Permission.bluetoothConnect.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (context.mounted) {
        AppToast.show(context, 'Allow Nearby devices permission to print — then tap Print again.');
      }
      return false;
    }
    final List<BluetoothDevice> bonded;
    try {
      bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (_) {
      if (context.mounted) AppToast.error(context, 'Bluetooth is off or unavailable — turn it on and retry.');
      return false;
    }
    if (!context.mounted) return false;
    final printers = bonded.where((d) => !d.isConnected).toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    if (printers.isEmpty) {
      AppToast.show(context,
          'No paired printer found. Pair your Bluetooth receipt printer in Android Settings first, then tap Print.');
      return false;
    }
    final picked = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Choose a Bluetooth printer',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          for (final d in printers)
            ListTile(
              leading: const Icon(Icons.print_outlined, color: AppColors.forest),
              title: Text(d.name ?? 'Unnamed device', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(d.address, style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, d),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return false;

    AppToast.show(context, 'Sending to ${picked.name ?? 'printer'}…');
    try {
      final bytes = await buildEscPos(data);
      final conn = await BluetoothConnection.toAddress(picked.address).timeout(const Duration(seconds: 10));
      conn.output.add(Uint8List.fromList(bytes));
      await conn.output.allSent;
      // Cheap printers need a beat after the last byte before the cut.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      conn.dispose();
      if (context.mounted) AppToast.show(context, 'Waybill sent to ${picked.name ?? 'printer'} ✓');
      return true;
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context,
            'Could not print on ${picked.name ?? 'printer'}. Check it is on and in range, then retry.');
      }
      return false;
    }
  }

  /// Split a long line at word boundaries so nothing runs past the printable
  /// width and nothing is cut off mid-word.
  static List<String> _wrapWords(String text, int maxLen) {
    final words = text.split(' ');
    final out = <String>[];
    String current = '';
    for (final w in words) {
      final next = current.isEmpty ? w : '$current $w';
      if (next.length <= maxLen) {
        current = next;
      } else {
        if (current.isNotEmpty) out.add(current);
        // absurdly long single token — hard split so nothing is lost
        if (w.length > maxLen) {
          for (var i = 0; i < w.length; i += maxLen) {
            out.add(w.substring(i, (i + maxLen).clamp(0, w.length)));
          }
          current = '';
        } else {
          current = w;
        }
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  /// ESC/POS bytes for the whole receipt (58 mm default — centred text still
  /// fills an 80 mm roll gracefully).
  static Future<List<int>> buildEscPos(WaybillPrintData d) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    final out = <int>[];

    // Header
    out.addAll(gen.text('DROPOFF', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    out.addAll(gen.text(d.title, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    out.addAll(gen.text('Home-to-depot pickup · Zambia', styles: const PosStyles(align: PosAlign.center)));
    out.addAll(gen.feed(1));

    // Reference + scannable CODE128 (the screen print says the text ref is
    // the source of truth — the barcode is a convenience for counters).
    out.addAll(gen.text(d.ref, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    out.addAll(gen.feed(1));
    try {
      // CODE128 data must be per-character (the converter reads one code unit
      // per list element).
      out.addAll(gen.barcode(Barcode.code128(d.ref.split('')),
          width: 2, height: 60, textPos: BarcodeText.none));
    } catch (_) {/* non-ASCII refs simply skip the barcode */}
    out.addAll(gen.feed(1));

    // Route hero
    out.addAll(gen.text(d.route, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    if (d.courierLine.isNotEmpty) {
      out.addAll(gen.text(d.courierLine, styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
    }
    out.addAll(gen.text(d.statusLabel.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true)));
    out.addAll(gen.feed(1));

    void section(String title, List<(String, String)> rows) {
      out.addAll(gen.hr());
      out.addAll(gen.text(title.toUpperCase(), styles: const PosStyles(bold: true, fontType: PosFontType.fontB)));
      for (final (label, value) in rows) {
        if (value.trim().isEmpty) continue;
        out.addAll(gen.row([
          PosColumn(text: label, width: 5, styles: const PosStyles(fontType: PosFontType.fontB)),
          PosColumn(
              text: value,
              width: 7,
              styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]));
      }
    }

    section('ROUTE & DEPOT', [
      ('From', d.from),
      ('To (final)', d.to),
      ('Drop-off branch', d.branch),
      ('Courier', d.courier),
      ('Pickup point', d.pickupAddress),
      ('Pickup window', d.pickupWindow),
      ('Scheduled slot', d.scheduledSlot),
    ]);
    section('PARCEL', [
      ('Size', d.size),
      ('Items', d.parcels),
      ('Vehicle', d.vehicle),
      ('Description', d.description),
    ]);
    section('VALUE', [
      ('Declared value', d.declaredValue),
      ('Partner waybill', d.partnerWaybill),
    ]);
    section('FEES & PAYMENT', [
      ('Rider fee', d.riderFee),
      ('Last-mile fee', d.lastMileFee),
      ('Promo', d.promo),
      ('DropOff due', d.dropoffDue),
      ('Courier fare', d.courierFare),
      ('Payment', d.paymentMethod),
    ]);
    section('SENDER', [
      ('Name', d.senderName),
      ('Phone', d.senderPhone),
    ]);
    section('RECIPIENT', [
      ('Name', d.recipientName),
      ('Phone', d.recipientPhone),
    ]);
    section('BOOKING', [
      ('Reference', d.reference),
      ('Dispatch ref', d.dispatchRef),
      ('Booked', d.bookedAt),
      ('Rider', d.rider),
    ]);

    // Recipient tracking as QR — the counter/recipient can scan it directly.
    if (d.trackingUrl != null && d.trackingUrl!.trim().isNotEmpty) {
      out.addAll(gen.hr());
      out.addAll(gen.text('RECIPIENT TRACKING', styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB)));
      try {
        out.addAll(gen.qrcode(d.trackingUrl!.trim(), size: QRSize.size5, cor: QRCorrection.L));
      } catch (_) {
        for (final line in _wrapWords(d.trackingUrl!.trim(), 38)) {
          out.addAll(gen.text(line, styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
        }
      }
    }

    out.addAll(gen.hr());
    for (final line in _wrapWords(
      'The rider pays the depot fare at the counter. The sender repays the receipt plus processing fee in DropOff to reimburse the rider. Keep this waybill until the item is lodged.',
      40,
    )) {
      out.addAll(gen.text(line,
          styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
    }
    // Cheap portables ship with a built-in cutter that slices the last printed
    // line if the feed is too short — give the cutter a clear margin.
    out.addAll(gen.feed(4));
    try {
      out.addAll(gen.cut());
    } catch (_) {/* some portables lack the cutter — paper tear works */}
    return out;
  }
}

/// All the receipt fields, decoupled from Flutter widgets so the printer can
/// run from anywhere (waybill screen now; rider/counter later).
class WaybillPrintData {
  final String title; // e.g. PLATINUM COUNTER WAYBILL
  final String ref;
  final String route;
  final String courierLine;
  final String statusLabel;
  final String from;
  final String to;
  final String branch;
  final String courier;
  final String pickupAddress;
  final String pickupWindow;
  final String scheduledSlot;
  final String size;
  final String parcels;
  final String vehicle;
  final String description;
  final String declaredValue;
  final String partnerWaybill;
  final String riderFee;
  final String lastMileFee;
  final String promo;
  final String dropoffDue;
  final String courierFare;
  final String paymentMethod;
  final String senderName;
  final String senderPhone;
  final String recipientName;
  final String recipientPhone;
  final String reference;
  final String dispatchRef;
  final String bookedAt;
  final String rider;
  final String? trackingUrl;

  const WaybillPrintData({
    required this.title,
    required this.ref,
    required this.route,
    required this.courierLine,
    required this.statusLabel,
    required this.from,
    required this.to,
    required this.branch,
    required this.courier,
    required this.pickupAddress,
    required this.pickupWindow,
    required this.scheduledSlot,
    required this.size,
    required this.parcels,
    required this.vehicle,
    required this.description,
    required this.declaredValue,
    required this.partnerWaybill,
    required this.riderFee,
    required this.lastMileFee,
    required this.promo,
    required this.dropoffDue,
    required this.courierFare,
    required this.paymentMethod,
    required this.senderName,
    required this.senderPhone,
    required this.recipientName,
    required this.recipientPhone,
    required this.reference,
    required this.dispatchRef,
    required this.bookedAt,
    required this.rider,
    this.trackingUrl,
  });
}
