import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/money.dart';
import 'quote_models.dart';

/// Renders a quotation as a shareable PDF document.
Future<Uint8List> buildQuotePdf(Quotation q, {required String issuerName}) {
  final doc = pw.Document(title: 'Quotation ${q.number}', author: issuerName);
  final totals = q.totals;
  final amounts = q.milestoneAmounts;
  final date = DateFormat('d MMM yyyy');
  String money(int minor) => Money.formatWithCode(minor, q.currency);
  const accent = PdfColor.fromInt(0xFF1F8F67);
  const muted = PdfColor.fromInt(0xFF6B7280);

  pw.Widget totalRow(String label, String value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(label, style: const pw.TextStyle(color: muted)),
            ),
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontWeight: bold ? pw.FontWeight.bold : null,
                ),
              ),
            ),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'QUOTATION',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(q.number, style: const pw.TextStyle(color: muted)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  issuerName,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Issued ${date.format(q.createdAt)}',
                  style: const pw.TextStyle(color: muted),
                ),
                if (q.validUntil != null)
                  pw.Text(
                    'Valid until ${date.format(q.validUntil!)}',
                    style: const pw.TextStyle(color: muted),
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 28),
        pw.Text(
          'PREPARED FOR',
          style: const pw.TextStyle(fontSize: 9, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          q.clientName,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        if (q.clientCompany != null) pw.Text(q.clientCompany!),
        if (q.clientEmail != null)
          pw.Text(q.clientEmail!, style: const pw.TextStyle(color: muted)),
        pw.SizedBox(height: 20),
        pw.Text(
          q.projectTitle,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        if (q.projectDescription.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            q.projectDescription,
            style: const pw.TextStyle(color: muted),
          ),
        ],
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['Description', 'Qty', 'Unit price', 'Amount'],
          data: [
            for (final i in q.items)
              [
                i.description,
                i.quantity == i.quantity.roundToDouble()
                    ? i.quantity.toInt().toString()
                    : i.quantity.toStringAsFixed(2),
                money(i.unitPriceMinor),
                money(i.amountMinor),
              ],
          ],
          border: null,
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: accent),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 7,
          ),
        ),
        pw.SizedBox(height: 12),
        totalRow('Subtotal', money(totals.subtotalMinor)),
        if (totals.discountMinor > 0)
          totalRow('Discount', '- ${money(totals.discountMinor)}'),
        if (q.taxRatePercent > 0)
          totalRow(
            'Tax (${q.taxRatePercent.toStringAsFixed(q.taxRatePercent % 1 == 0 ? 0 : 2)}%)',
            money(totals.taxMinor),
          ),
        pw.Divider(color: PdfColors.grey400),
        totalRow('Total', money(totals.totalMinor), bold: true),
        if (q.milestones.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text(
            'Payment schedule',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          for (var i = 0; i < q.milestones.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${q.milestones[i].title} (${q.milestones[i].percent}%)',
                    ),
                  ),
                  pw.Text(money(amounts[i])),
                ],
              ),
            ),
        ],
        if (q.notes.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text('Notes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(q.notes, style: const pw.TextStyle(color: muted)),
        ],
      ],
    ),
  );
  return doc.save();
}
