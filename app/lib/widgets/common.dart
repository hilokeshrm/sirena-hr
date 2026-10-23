import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';

/// Loads data once, shows a spinner / error with retry, and hands the result to [builder].
class Fetch<T> extends StatefulWidget {
  const Fetch({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Fetch<T>> createState() => _FetchState<T>();
}

class _FetchState<T> extends State<Fetch<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final next = widget.load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: C.red)));
        }
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(text, style: const TextStyle(fontSize: 14))),
      );
}

/// White card with a hairline border.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: color == Colors.white ? Border.all(color: C.grey) : null,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: box));
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(children: [Expanded(child: Text(text, style: display(18))), if (trailing != null) trailing!]),
      );
}

/// Status pill. Approved = black, pending = red on grey, declined/cancelled = grey.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});
  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'APPROVED' || 'DONE' || 'PUBLISHED' || 'ON_TRACK' => (C.ink, Colors.white),
      'PENDING_MANAGER' || 'PENDING_HR' || 'IN_REVIEW' || 'AT_RISK' || 'URGENT' => (C.grey, C.red),
      'DELAYED' || 'HIGH' => (C.red, Colors.white),
      _ => (C.grey, C.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label ?? leaveStatusLabel[status] ?? prettyEnum(status), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

}

/// Standard Indian food marks: green square + dot (veg), brown square + triangle (non-veg).
class FoodMark extends StatelessWidget {
  const FoodMark({super.key, required this.veg, this.size = 18});
  final bool veg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = veg ? C.veg : C.nonVeg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: color, width: size / 8), borderRadius: BorderRadius.circular(size / 6)),
      alignment: Alignment.center,
      child: veg
          ? Container(width: size * 0.45, height: size * 0.45, decoration: BoxDecoration(color: color, shape: BoxShape.circle))
          : CustomPaint(size: Size(size * 0.5, size * 0.42), painter: _Triangle(color)),
    );
  }
}

class _Triangle extends CustomPainter {
  _Triangle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width / 2, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _Triangle old) => old.color != color;
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.dark = false});
  final String name;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: dark ? C.red : C.grey, borderRadius: BorderRadius.circular(size * 0.33)),
        child: Text(initials(name), style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.32, color: dark ? Colors.white : C.ink)),
      );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Runs an API action, showing errors as a snackbar. Returns the result or null on failure.
Future<T?> attempt<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } on ApiError catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Something went wrong: $e');
  }
  return null;
}

Future<String?> askText(BuildContext context, {required String title, String label = 'Note', String action = 'Save'}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, decoration: inputDeco(label), autofocus: true, maxLines: 3, minLines: 1),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(action)),
      ],
    ),
  );
}

/// Centers content and caps its width on wide screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 900, this.onRefresh});
  final List<Widget> children;
  final double maxWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(color: C.red, onRefresh: onRefresh!, child: list);
  }
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
