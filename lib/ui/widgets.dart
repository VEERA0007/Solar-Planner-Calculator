import 'package:flutter/material.dart';
import 'theme.dart';

/// Rounded pill tab bar used by the Settings and Profile dialogs.
class PillTabs extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const PillTabs({super.key, required this.controller, required this.labels});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(14)),
        labelColor: C.sky,
        unselectedLabelColor: C.mute,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        splashBorderRadius: BorderRadius.circular(14),
        tabs: [for (final l in labels) Tab(height: 40, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis))],
      ),
    );
  }
}

/// A rounded section card with an icon title row and an optional tag on the right.
class SectionCard extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String? title;
  final Widget? tag;
  final Widget child;
  final Color? tint, border;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    this.icon,
    this.iconColor,
    this.title,
    this.tag,
    required this.child,
    this.tint,
    this.border,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? C.card2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border ?? C.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: iconColor ?? C.blue), const SizedBox(width: 8)],
              Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (tag != null) tag!,
            ]),
          ),
        child,
      ]),
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final bool outlined;
  const Tag(this.text, this.color, {super.key, this.outlined = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(99),
          border: outlined ? Border.all(color: color) : null,
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// Label above a field (as in the reference design) with an optional icon.
class FieldLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  const FieldLabel(this.text, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: C.mute), const SizedBox(width: 5)],
          Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

InputDecoration plainField({String? error, Widget? suffix}) => InputDecoration(
      errorText: error,
      suffixIcon: suffix,
      filled: true,
      fillColor: C.card2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.sky, width: 1.6)),
    );

/// Dialog footer: Cancel (muted) + primary action with a save icon.
class DialogFooter extends StatelessWidget {
  final String cancel, save;
  final VoidCallback onCancel, onSave;
  const DialogFooter({super.key, required this.cancel, required this.save, required this.onCancel, required this.onSave});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Divider(color: C.line, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(children: [
            Expanded(
              flex: 4,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  backgroundColor: C.chip,
                  foregroundColor: C.text,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(cancel, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined, size: 20),
                label: Text(save, style: const TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: const Color(0xFF0A84D8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ]),
        ),
      ]);
}
