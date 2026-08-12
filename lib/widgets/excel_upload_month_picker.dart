import 'package:flutter/material.dart';

/// Formats a month as `YYYY-MM` for the POD blob-upload `excel_month` field.
String formatExcelUploadMonth(DateTime month) {
  final y = month.year.toString().padLeft(4, '0');
  final m = month.month.toString().padLeft(2, '0');
  return '$y-$m';
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Human label for the Excel month (e.g. `June 2026`).
String formatExcelUploadMonthLabel(DateTime month) {
  return '${_monthNames[month.month - 1]} ${month.year}';
}

DateTime currentExcelUploadMonth() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

/// Month/year dropdown used only when the upload batch contains Excel files.
///
/// Mirrors the dashboard's 24-month pattern so the look stays familiar without
/// tying this screen to dashboard state.
class ExcelUploadMonthPicker extends StatelessWidget {
  const ExcelUploadMonthPicker({
    super.key,
    required this.selectedMonth,
    required this.onMonthChanged,
    this.title = 'Select Excel Month',
    this.subtitle =
        'Used as a fallback when the spreadsheet has no invoice date.',
  });

  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthChanged;
  final String title;
  final String subtitle;

  static String _key(DateTime d) => formatExcelUploadMonth(d);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      24,
      (i) => DateTime(now.year, now.month - i, 1),
    );
    final selectedKey = _key(selectedMonth);

    // Keep a selectable value even if the stored month is outside the window.
    final values = {
      for (final m in months) _key(m),
    };
    if (!values.contains(selectedKey)) {
      months.insert(0, DateTime(selectedMonth.year, selectedMonth.month, 1));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8E0E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A0A8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF00A0A8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E8EC)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedKey,
                isExpanded: true,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
                items: [
                  for (final m in months)
                    DropdownMenuItem<String>(
                      value: _key(m),
                      child: Text(formatExcelUploadMonthLabel(m)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final parts = v.split('-');
                  if (parts.length != 2) return;
                  final y = int.tryParse(parts[0]);
                  final mm = int.tryParse(parts[1]);
                  if (y == null || mm == null) return;
                  onMonthChanged(DateTime(y, mm, 1));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
