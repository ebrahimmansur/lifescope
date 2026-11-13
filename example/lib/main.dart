// Run `flutter create .` in this folder once to generate the platform
// runners, then `flutter run -d windows` (or macos/linux) to try the exit
// guard. Hiding and restoring the window shows the lifecycle callbacks.

import 'package:flutter/material.dart';
import 'package:lifescope/lifescope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // One scope for the whole app, created up front so services can use it.
  final lifecycle = LifeScope();
  final log = ActivityLog(lifecycle);
  final session = ReviewSession(lifecycle);

  runApp(
    LifeScopeProvider.value(
      scope: lifecycle,
      child: ExampleApp(log: log, session: session),
    ),
  );
}

/// A long-lived service that records every lifecycle change.
class ActivityLog extends ChangeNotifier {
  ActivityLog(LifeScope lifecycle) {
    lifecycle.listen(onStateChange: (state) => add('state: ${state.name}'));
  }

  final List<String> entries = [];

  void add(String entry) {
    entries.insert(0, entry);
    notifyListeners();
  }
}

/// A business controller that checkpoints progress when the app is hidden.
class ReviewSession {
  ReviewSession(LifeScope lifecycle) {
    _subscription = lifecycle.listen(onHide: checkpoint);
  }

  late final LifeScopeSubscription _subscription;
  int reviewed = 0;
  int saved = 0;

  Future<void> checkpoint() async {
    // Pretend to write to disk.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    saved = reviewed;
  }

  void close() => _subscription.cancel();
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.log, required this.session});

  final ActivityLog log;
  final ReviewSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lifescope example',
      home: HomePage(log: log, session: session),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.log, required this.session});

  final ActivityLog log;
  final ReviewSession session;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _dirty = false;

  Future<AppExitResponse> _confirmExit() async {
    if (!_dirty) return AppExitResponse.exit;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = LifeScope.of(context);

    // A widget that reacts to visibility, cleaned up automatically.
    return LifeScopeListener(
      onHide: () => widget.log.add('paused animations'),
      onShow: () => widget.log.add('resumed animations'),
      // A desktop guard that only exists while this page is shown.
      child: LifeScopeExitGuard(
        onExitRequested: _confirmExit,
        child: Scaffold(
          appBar: AppBar(
            title: ValueListenableBuilder(
              valueListenable: lifecycle.state,
              builder: (context, state, _) =>
                  Text('State: ${state?.name ?? 'unknown'}'),
            ),
          ),
          body: Column(
            children: [
              SwitchListTile(
                title: const Text('Unsaved changes'),
                subtitle: const Text('Try closing the window with this on.'),
                value: _dirty,
                onChanged: (value) => setState(() => _dirty = value),
              ),
              ListTile(
                title: Text('Cards reviewed: ${widget.session.reviewed}'),
                subtitle: Text('Saved on hide: ${widget.session.saved}'),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => widget.session.reviewed++),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.log,
                  builder: (context, _) => ListView(
                    children: [
                      for (final entry in widget.log.entries)
                        ListTile(dense: true, title: Text(entry)),
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
