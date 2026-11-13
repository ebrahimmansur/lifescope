import 'dart:async';
import 'dart:collection';

/// A handle to a lifecycle listener or exit guard.
///
/// Call [cancel] when the owner of the subscription is disposed. After that,
/// none of its callbacks will be called again.
abstract interface class LifeScopeSubscription {
  /// Whether the subscription is still receiving callbacks.
  bool get isActive;

  /// Stops the subscription. Callbacks that are queued but not started yet
  /// are dropped. A callback that is already running is left to finish.
  ///
  /// Calling this more than once has no effect.
  void cancel();
}

/// A [LifeScopeSubscription] that runs [onCancel] the first time it is
/// cancelled.
class CallbackSubscription implements LifeScopeSubscription {
  /// Creates a subscription that calls [onCancel] once.
  CallbackSubscription(this._onCancel);

  final void Function() _onCancel;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _onCancel();
  }
}

/// A unit of work run by [SerialQueue].
typedef QueueTask = FutureOr<void> Function();

/// Runs tasks one after another.
///
/// A task that completes synchronously runs right away, inside [add]. A task
/// that returns a future holds back the following tasks until it completes.
/// Errors are passed to [onError] and never stop the queue.
///
/// If [timeout] is set, the queue waits at most that long for an async task.
/// It then reports a [TimeoutException] and moves on. The slow task is not
/// cancelled, the queue just stops waiting for it.
class SerialQueue {
  /// Creates an empty queue.
  SerialQueue({required this.onError, this.timeout});

  /// Called with any error thrown by a task.
  final void Function(Object error, StackTrace stack) onError;

  /// How long to wait for an async task before moving on.
  final Duration? timeout;

  final Queue<QueueTask> _pending = Queue<QueueTask>();
  bool _busy = false;
  bool _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Schedules [task]. Ignored once the queue is closed.
  void add(QueueTask task) {
    if (_closed) return;
    _pending.add(task);
    if (!_busy) _drain();
  }

  /// Drops pending tasks and ignores new ones.
  void close() {
    _closed = true;
    _pending.clear();
  }

  void _drain() {
    _busy = true;
    while (_pending.isNotEmpty && !_closed) {
      final task = _pending.removeFirst();
      final FutureOr<void> result;
      try {
        result = task();
      } catch (error, stack) {
        onError(error, stack);
        continue;
      }
      if (result is Future<void>) {
        final timeout = this.timeout;
        final pending = timeout == null ? result : result.timeout(timeout);
        pending.then<void>((_) {}, onError: onError).whenComplete(_drain);
        return;
      }
    }
    _busy = false;
  }
}
