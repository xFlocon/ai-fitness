import 'package:material_ui/material_ui.dart';

import '../core/ai.dart';

class PageBody extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final Widget? action;
  const PageBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 110),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle.toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                    ),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  const Panel({super.key, required this.child, this.onTap, this.color});
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  const EmptyState(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.auto_awesome_outlined,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class Load<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T) builder;
  const Load({super.key, required this.future, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyState(
          'Não foi possível carregar',
          apiError(snapshot.error!),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

void notice(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String label = 'Confirmar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> ask(
  BuildContext context,
  String title, {
  String initial = '',
  bool numeric = false,
  int lines = 1,
  bool secret = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: secret,
        maxLines: lines,
        maxLength: lines > 1 ? 4000 : 150,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  // Dialog closing transition may still hold the controller until next frame.
  // Route transition may retain field briefly; dispose once transition completes.
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return result;
}

Widget field(
  TextEditingController controller,
  String label, {
  bool numeric = false,
  bool secret = false,
  int lines = 1,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    obscureText: secret,
    maxLines: lines,
    maxLength: lines > 1 ? 4000 : 500,
    buildCounter: (
      _, {
      required currentLength,
      required isFocused,
      required maxLength,
    }) => null,
  ),
);
