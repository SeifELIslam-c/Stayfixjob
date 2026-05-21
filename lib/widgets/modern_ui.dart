import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const Color luxeBg = Colors.black;
const Color luxeSurface = Color(0xFF0B0B0F);
const Color luxeCard = Color(0xFF18181B);
const Color luxeBorder = Color(0xFF2F3037);
const Color luxeBlue = Color(0xFF0A66D8);

PreferredSizeWidget modernHeader({
  required BuildContext context,
  required String title,
  String? subtitle,
  bool showBack = true,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: Colors.black,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: showBack
        ? IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          )
        : null,
    titleSpacing: showBack ? 0 : 24,
    centerTitle: false,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
    actions: actions,
  );
}

Widget sectionLabel(String title, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.grey[500], size: 16),
          const SizedBox(width: 8),
        ],
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

BoxDecoration luxeBox({
  Color color = luxeCard,
  Color borderColor = luxeBorder,
  double radius = 18,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 22,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

InputDecoration modernInputDecoration({
  required String label,
  required IconData icon,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(color: Colors.grey[500]),
    hintStyle: TextStyle(color: Colors.grey[600]),
    prefixIcon: Icon(icon, color: Colors.grey[500], size: 19),
    filled: true,
    fillColor: luxeCard,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: luxeBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.white, width: 1.2),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  );
}

Future<DateTime?> showModernDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String helpText = 'Selectionnez une date',
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    cancelText: 'Annuler',
    confirmText: 'Choisir',
    builder: (ctx, child) {
      return Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            surface: luxeSurface,
            onSurface: Colors.white,
            secondary: luxeBlue,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: luxeSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: luxeBorder),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: luxeSurface,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: luxeCard,
            headerForegroundColor: Colors.white,
            dividerColor: luxeBorder,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: luxeBorder),
            ),
            dayStyle: const TextStyle(fontWeight: FontWeight.w600),
            weekdayStyle: TextStyle(
              color: Colors.grey[500],
              fontWeight: FontWeight.w800,
            ),
            yearStyle: const TextStyle(fontWeight: FontWeight.w700),
            todayBorder: const BorderSide(color: Colors.white),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        child: child!,
      );
    },
  );
}

Future<T?> showModernBottomSheet<T>({
  required BuildContext context,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: luxeSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: luxeBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

Widget modernOptionTile({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  bool destructive = false,
}) {
  final color = destructive ? Colors.red[400]! : Colors.white;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: destructive
              ? Colors.red.withValues(alpha: 0.08)
              : const Color(0xFF15151A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: destructive ? Colors.red.withValues(alpha: 0.3) : luxeBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.grey[600], size: 18),
          ],
        ),
      ),
    ),
  );
}
