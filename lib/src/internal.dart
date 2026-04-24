// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mnsml/mnsml.dart';
import 'package:mnsml/src/core.dart' show ReactionImpl;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// `true` if a stack frame indicating where an [Observer] was created should be
/// included in its name. This is useful during debugging to identify the source
/// of warnings or errors.
///
/// Note that stack frames are only included in debug builds.
bool debugAddStackTraceInObserverName = true;

/// A [StatelessObserverWidget] that delegate its [build] method to [builder].
///
/// See also:
///
/// - [Builder], which is the same thing but for [StatelessWidget] instead.
class Observer extends StatelessObserverWidget {
  // ignore: prefer_const_constructors_in_immutables
  Observer({
    super.key,
    required this.builder,
    super.name,
    super.warnWhenNoObservables,
  }) : debugConstructingStackFrame = debugFindConstructingStackFrame();

  /// Observer which excludes the child branch from being rebuilt
  ///
  /// - [builder] is a builder function with a child widget as a parameter;
  ///
  /// - [child] is the widget to pass to the [builder] function.
  // ignore: prefer_const_constructors_in_immutables
  Observer.withBuiltChild({
    super.key,
    required Widget Function(BuildContext, Widget) builder,
    required Widget child,
    super.name,
    super.warnWhenNoObservables,
  }) : debugConstructingStackFrame = debugFindConstructingStackFrame(),
       builder = ((context) => builder(context, child));

  final WidgetBuilder builder;

  /// The stack frame pointing to the source that constructed this instance.
  final String? debugConstructingStackFrame;

  @override
  String getName() =>
      super.getName() +
      (debugConstructingStackFrame != null
          ? '\n$debugConstructingStackFrame'
          : '');

  @override
  Widget build(BuildContext context) => builder.call(context);

  /// Matches constructor stack frames, in both VM and web environments.
  static final _constructorStackFramePattern = RegExp(r'\bnew\b');

  static final _stackFrameCleanUpPattern = RegExp(r'^#\d+\s+(.*)\$');

  /// Finds the first non-constructor frame in the stack trace.
  ///
  /// [stackTrace] defaults to [StackTrace.current].
  @visibleForTesting
  static String? debugFindConstructingStackFrame([StackTrace? stackTrace]) {
    String? stackFrame;

    assert(() {
      if (debugAddStackTraceInObserverName) {
        final stackTraceString = (stackTrace ?? StackTrace.current).toString();
        final rawStackFrame = LineSplitter.split(stackTraceString)
            // We are skipping frames representing:
            // 1. The anonymous function in the assert
            // 2. The debugFindConstructingStackFrame method
            // 3. The constructor invoking debugFindConstructingStackFrame
            //
            // The 4th frame is either user source (which is what we want), or
            // an Observer subclass' constructor (which we skip past with the
            // regex)
            .skip(3)
            // Search for the first non-constructor frame
            .firstWhere(
              (frame) => !_constructorStackFramePattern.hasMatch(frame),
              orElse: () => '',
            );

        final stackFrameCore = _stackFrameCleanUpPattern
            .firstMatch(rawStackFrame)
            ?.group(1);
        final cleanedStackFrame =
            stackFrameCore == null
                ? null
                : 'Observer constructed from: $stackFrameCore';

        stackFrame = cleanedStackFrame;
      }

      return true;
    }());

    return stackFrame;
  }
}

/// Whether to warn when there is no observables in the builder function
bool enableWarnWhenNoObservables = true;

/// Observer observes the observables used in the `build` method and rebuilds
/// the Widget whenever any of them change. There is no need to do any other
/// wiring besides simply referencing the required observables.
///
/// Internally, [ObserverWidgetMixin] uses a [Reaction] around the `build`
/// method.
///
/// If your `build` method does not contain any observables,
/// [ObserverWidgetMixin] will print a warning on the console. This is a
/// debug-time hint to let you know that you are not observing any observables.
mixin ObserverWidgetMixin on Widget {
  /// An identifiable name that can be overriden for debugging.
  String getName();

  /// The context within which its reaction should be run. It is the
  /// [mainContext] in most cases.
  ReactiveContext getContext() => mainContext;

  /// A convenience method used for testing.
  @visibleForTesting
  Reaction createReaction(
    Function() onInvalidate, {
    Function(Object, Reaction)? onError,
  }) => ReactionImpl(
    getContext(),
    onInvalidate,
    name: getName(),
    onError: onError,
  );

  /// Convenience method to output console messages as debugging output. Logging
  /// usually happens when some internal error needs to be surfaced to the user.
  void log(String msg) {
    debugPrint(msg);
  }

  /// Whether to warn when there is no observables in the builder function
  /// null means true
  bool? get warnWhenNoObservables => null;

  // We don't override `createElement` to specify that it should return a
  // `ObserverElementMixin` as it'd make the mixin impossible to use.
}

/// A mixin that overrides [build] to listen to the observables used by
/// [ObserverWidgetMixin].
mixin ObserverElementMixin on ComponentElement {
  ReactionImpl get reaction => _reaction!;

  // null means it is unmounted
  ReactionImpl? _reaction;

  // Not using the original `widget` getter as it would otherwise make the mixin
  // impossible to use
  ObserverWidgetMixin get _widget => widget as ObserverWidgetMixin;

  @override
  void mount(Element? parent, dynamic newSlot) {
    _reaction =
        _widget.createReaction(
              invalidate,
              onError: (e, _) {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    library: 'flutter_mnsml',
                    exception: e,
                    stack: e is Error ? e.stackTrace : null,
                    context: ErrorDescription(
                      'From reaction of ${_widget.getName()} of type $runtimeType.',
                    ),
                  ),
                );
              },
            )
            as ReactionImpl;
    super.mount(parent, newSlot);
  }

  void invalidate() => _markNeedsBuildImmediatelyOrDelayed();

  void _markNeedsBuildImmediatelyOrDelayed() async {
    // reference
    // 1. https://github.com/mnsmljs/mnsml.dart/issues/768
    // 2. https://stackoverflow.com/a/64702218/4619958
    // 3. https://stackoverflow.com/questions/71367080

    // if there's a current frame,
    final schedulerPhase =
        _ambiguate(SchedulerBinding.instance)!.schedulerPhase;
    final shouldWait =
        // surely, `idle` is ok
        schedulerPhase != SchedulerPhase.idle &&
        // By experience, it is safe to do something like
        // `SchedulerBinding.addPostFrameCallback((_) => someObservable.value = newValue)`
        // So it is safe if we are in this phase
        schedulerPhase != SchedulerPhase.postFrameCallbacks;
    if (shouldWait) {
      // uncomment to log
      // print('hi wait phase=$schedulerPhase');

      // wait for the end of that frame.
      await _ambiguate(SchedulerBinding.instance)!.endOfFrame;

      // If it is disposed after this frame, we should no longer call `markNeedsBuild`
      if (_reaction == null) return;
    }

    markNeedsBuild();
  }

  @override
  Widget build() {
    Widget? built;

    reaction.track(() {
      built = super.build();
    });

    if (enableWarnWhenNoObservables &&
        (_widget.warnWhenNoObservables ?? true) &&
        !reaction.hasObservables) {
      _widget.log(
        'No observables detected in the build method of ${reaction.name}',
      );
    }

    // This "throw" is better than a "LateInitializationError"
    // which confused the user. Please see #780 for details.
    if (built == null) {
      throw Exception(
        'Error happened when building ${_widget.runtimeType}, but it was captured since disableErrorBoundaries==true',
      );
    }

    return built!;
  }

  @override
  void unmount() {
    _reaction!.dispose();
    _reaction = null;
    super.unmount();
  }
}

/// This allows a value of type T or T?
/// to be treated as a value of type T?.
///
/// We use this so that APIs that have become
/// non-nullable can still be used with `!` and `?`
/// to support older versions of the API as well.
T? _ambiguate<T>(T? value) => value;

/// A [StatefulWidget] that rebuilds when an [Observable] used inside
/// [State.build] updates.
///
/// See also:
///
/// - [Observer], which subclass this interface and delegate its `build` to a
///   callback.
/// - [StatelessObserverWidget], similar to this class, but with no [State].
abstract class StatefulObserverWidget extends StatefulWidget
    with ObserverWidgetMixin {
  /// Initializes [key], [context] and [name] for subclasses.
  const StatefulObserverWidget({
    super.key,
    ReactiveContext? context,
    String? name,
  }) : _name = name,
       _context = context;

  final String? _name;
  final ReactiveContext? _context;

  @override
  String getName() => _name ?? '$this';

  @override
  ReactiveContext getContext() => _context ?? super.getContext();

  @override
  StatefulObserverElement createElement() => StatefulObserverElement(this);
}

/// An [Element] that uses a [StatefulObserverWidget] as its configuration.
class StatefulObserverElement extends StatefulElement
    with ObserverElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  StatefulObserverElement(StatefulObserverWidget widget) : super(widget);

  @override
  StatefulObserverWidget get widget => super.widget as StatefulObserverWidget;
}

/// A [StatelessWidget] that rebuilds when an [Observable] used inside [build]
/// updates.
///
/// See also:
///
/// - [Observer], which subclass this interface and delegate its `build`
///   to a callback.
/// - [StatefulObserverWidget], similar to this class, but that has a [State].
abstract class StatelessObserverWidget extends StatelessWidget
    with ObserverWidgetMixin {
  /// Initializes [key], [context] and [name] for subclasses.
  const StatelessObserverWidget({
    super.key,
    ReactiveContext? context,
    String? name,
    this.warnWhenNoObservables,
  }) : _name = name,
       _context = context;

  final String? _name;
  final ReactiveContext? _context;
  @override
  final bool? warnWhenNoObservables;

  @override
  String getName() => _name ?? '$this';

  @override
  ReactiveContext getContext() => _context ?? super.getContext();

  @override
  StatelessObserverElement createElement() => StatelessObserverElement(this);
}

/// An [Element] that uses a [StatelessObserverWidget] as its configuration.
class StatelessObserverElement extends StatelessElement
    with ObserverElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  StatelessObserverElement(StatelessObserverWidget super.widget);

  @override
  StatelessObserverWidget get widget => super.widget as StatelessObserverWidget;
}

/// A builder function that creates a reaction
typedef ReactionBuilderFunction =
    ReactionDisposer Function(BuildContext context);

/// ReactionBuilder is useful for triggering reactions via a builder function rather
/// than creating a custom StatefulWidget for handling the same.
/// Without a [ReactionBuilder] you would normally have to create a StatefulWidget
/// where the `initState()` would be used to setup the reaction and then dispose it off
/// in the `dispose()` method.
///
/// Although simple, this little helper Widget eliminates the need to create such a
/// widget and handles the lifetime of the reaction correctly. To use it, pass a
/// [builder] that takes in a [BuildContext] and prepares the reaction. It should
/// end up returning a [ReactionDisposer]. This will be disposed when the [ReactionBuilder]
/// is disposed. The [child] Widget gets rendered as part of the build process.
class ReactionBuilder extends SingleChildStatefulWidget {
  final ReactionBuilderFunction builder;

  const ReactionBuilder({super.key, super.child, required this.builder});

  @override
  ReactionBuilderState createState() => ReactionBuilderState();
}

@visibleForTesting
class ReactionBuilderState extends SingleChildState<ReactionBuilder> {
  late ReactionDisposer _disposeReaction;

  bool get isDisposed => _disposeReaction.reaction.isDisposed;

  @override
  void initState() {
    super.initState();

    _disposeReaction = widget.builder(context);
  }

  @override
  void dispose() {
    _disposeReaction();
    super.dispose();
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    assert(
      child != null,
      '''${widget.runtimeType} used outside of MultiReactionBuilder must specify a child''',
    );

    return child!;
  }
}

/// {@template multi_reaction_builder}
/// Merges multiple [ReactionBuilder] widgets into one widget tree.
///
/// [MultiReactionBuilder] improves the readability and eliminates the need
/// to nest multiple [ReactionBuilder]s.
///
/// By using [MultiReactionBuilder] we can go from:
///
/// ```dart
/// ReactionBuilder(
///   builder: (context) {},
///   child: ReactionBuilder(
///     builder: (context) {},
///     child: ReactionBuilder(
///       builder: (context) {},
///       child: ChildA(),
///     ),
///   ),
/// )
/// ```
///
/// to:
///
/// ```dart
/// MultiReactionBuilder(
///   builders: [
///     ReactionBuilder(
///       builder: (context) {},
///     ),
///     ReactionBuilder(
///       builder: (context) {},
///     ),
///     ReactionBuilder(
///       builder: (context) {},
///     ),
///   ],
///   child: ChildA(),
/// )
/// ```
///
/// [MultiReactionBuilder] converts the [ReactionBuilder] list into a tree of nested
/// [ReactionBuilder] widgets.
/// As a result, the only advantage of using [MultiReactionBuilder] is improved
/// readability due to the reduction in nesting and boilerplate.
/// {@endtemplate}
class MultiReactionBuilder extends StatelessWidget {
  /// {@macro multi_reaction_builder}
  const MultiReactionBuilder({
    super.key,
    required this.builders,
    required this.child,
  });

  final List<ReactionBuilder> builders;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return builders.reversed.fold<Widget>(
      child,
      (Widget innerChild, ReactionBuilder builder) => ReactionBuilder(
        key: builder.key,
        builder: builder.builder,
        child: innerChild,
      ),
    );
  }
}

/// A widget that simplify the writing of deeply nested widget trees.
///
/// It relies on the new kind of widget [SingleChildWidget], which has two
/// concrete implementations:
/// - [SingleChildStatelessWidget]
/// - [SingleChildStatefulWidget]
///
/// They are both respectively a [SingleChildWidget] variant of [StatelessWidget]
/// and [StatefulWidget].
///
/// The difference between a widget and its single-child variant is that they have
/// a custom `build` method that takes an extra parameter.
///
/// As such, a `StatelessWidget` would be:
///
/// ```dart
/// class MyWidget extends StatelessWidget {
///   MyWidget({Key key, this.child}): super(key: key);
///
///   final Widget child;
///
///   @override
///   Widget build(BuildContext context) {
///     return SomethingWidget(child: child);
///   }
/// }
/// ```
///
/// Whereas a [SingleChildStatelessWidget] would be:
///
/// ```dart
/// class MyWidget extends SingleChildStatelessWidget {
///   MyWidget({Key key, Widget child}): super(key: key, child: child);
///
///   @override
///   Widget buildWithChild(BuildContext context, Widget child) {
///     return SomethingWidget(child: child);
///   }
/// }
/// ```
///
/// This allows our new `MyWidget` to be used both with:
///
/// ```dart
/// MyWidget(
///   child: AnotherWidget(),
/// )
/// ```
///
/// and to be placed inside `children` of [Nested] like so:
///
/// ```dart
/// Nested(
///   children: [
///     MyWidget(),
///     ...
///   ],
///   child: AnotherWidget(),
/// )
/// ```
class Nested extends StatelessWidget implements SingleChildWidget {
  /// Allows configuring key, children and child
  Nested({Key? key, required List<SingleChildWidget> children, Widget? child})
    : assert(children.isNotEmpty),
      _children = children,
      _child = child,
      super(key: key);

  final List<SingleChildWidget> _children;
  final Widget? _child;

  @override
  Widget build(BuildContext context) {
    throw StateError('implemented internally');
  }

  @override
  _NestedElement createElement() => _NestedElement(this);
}

class _NestedElement extends StatelessElement
    with SingleChildWidgetElementMixin {
  _NestedElement(Nested widget) : super(widget);

  @override
  Nested get widget => super.widget as Nested;

  final nodes = <_NestedHookElement>{};

  @override
  Widget build() {
    _NestedHook? nestedHook;
    var nextNode = _parent?.injectedChild ?? widget._child;

    for (final child in widget._children.reversed) {
      nextNode =
          nestedHook = _NestedHook(
            owner: this,
            wrappedWidget: child,
            injectedChild: nextNode,
          );
    }

    if (nestedHook != null) {
      // We manually update _NestedHookElement instead of letter widgets do their thing
      // because an item N may be constant but N+1 not. So, if we used widgets
      // then N+1 wouldn't rebuild because N didn't change
      for (final node in nodes) {
        node
          ..wrappedChild = nestedHook!.wrappedWidget
          ..injectedChild = nestedHook.injectedChild;

        final next = nestedHook.injectedChild;
        if (next is _NestedHook) {
          nestedHook = next;
        } else {
          break;
        }
      }
    }

    return nextNode!;
  }
}

class _NestedHook extends StatelessWidget {
  _NestedHook({
    this.injectedChild,
    required this.wrappedWidget,
    required this.owner,
  });

  final SingleChildWidget wrappedWidget;
  final Widget? injectedChild;
  final _NestedElement owner;

  @override
  _NestedHookElement createElement() => _NestedHookElement(this);

  @override
  Widget build(BuildContext context) => throw StateError('handled internally');
}

class _NestedHookElement extends StatelessElement {
  _NestedHookElement(_NestedHook widget) : super(widget);

  @override
  _NestedHook get widget => super.widget as _NestedHook;

  Widget? _injectedChild;
  Widget? get injectedChild => _injectedChild;
  set injectedChild(Widget? value) {
    final previous = _injectedChild;
    if (value is _NestedHook &&
        previous is _NestedHook &&
        Widget.canUpdate(value.wrappedWidget, previous.wrappedWidget)) {
      // no need to rebuild the wrapped widget just for a _NestedHook.
      // The widget doesn't matter here, only its Element.
      return;
    }
    if (previous != value) {
      _injectedChild = value;
      visitChildren((e) => e.markNeedsBuild());
    }
  }

  SingleChildWidget? _wrappedChild;
  SingleChildWidget? get wrappedChild => _wrappedChild;
  set wrappedChild(SingleChildWidget? value) {
    if (_wrappedChild != value) {
      _wrappedChild = value;
      markNeedsBuild();
    }
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    widget.owner.nodes.add(this);
    _wrappedChild = widget.wrappedWidget;
    _injectedChild = widget.injectedChild;
    super.mount(parent, newSlot);
  }

  @override
  void unmount() {
    widget.owner.nodes.remove(this);
    super.unmount();
  }

  @override
  Widget build() {
    return wrappedChild!;
  }
}

/// A [Widget] that takes a single descendant.
///
/// As opposed to [ProxyWidget], it may have a "build" method.
///
/// See also:
/// - [SingleChildStatelessWidget]
/// - [SingleChildStatefulWidget]
abstract class SingleChildWidget implements Widget {
  @override
  SingleChildWidgetElementMixin createElement();
}

mixin SingleChildWidgetElementMixin on Element {
  _NestedHookElement? _parent;

  @override
  void mount(Element? parent, dynamic newSlot) {
    if (parent is _NestedHookElement?) {
      _parent = parent;
    }
    super.mount(parent, newSlot);
  }

  @override
  void activate() {
    super.activate();
    visitAncestorElements((parent) {
      if (parent is _NestedHookElement) {
        _parent = parent;
      }
      return false;
    });
  }
}

/// A [StatelessWidget] that implements [SingleChildWidget] and is therefore
/// compatible with [Nested].
///
/// Its [build] method must **not** be overriden. Instead use [buildWithChild].
abstract class SingleChildStatelessWidget extends StatelessWidget
    implements SingleChildWidget {
  /// Creates a widget that has exactly one child widget.
  const SingleChildStatelessWidget({Key? key, Widget? child})
    : _child = child,
      super(key: key);

  final Widget? _child;

  /// A [build] method that receives an extra `child` parameter.
  ///
  /// This method may be called with a `child` different from the parameter
  /// passed to the constructor of [SingleChildStatelessWidget].
  /// It may also be called again with a different `child`, without this widget
  /// being recreated.
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) => buildWithChild(context, _child);

  @override
  SingleChildStatelessElement createElement() {
    return SingleChildStatelessElement(this);
  }
}

/// An [Element] that uses a [SingleChildStatelessWidget] as its configuration.
class SingleChildStatelessElement extends StatelessElement
    with SingleChildWidgetElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildStatelessElement(SingleChildStatelessWidget widget)
    : super(widget);

  @override
  Widget build() {
    if (_parent != null) {
      return widget.buildWithChild(this, _parent!.injectedChild);
    }
    return super.build();
  }

  @override
  SingleChildStatelessWidget get widget =>
      super.widget as SingleChildStatelessWidget;
}

/// A [StatefulWidget] that is compatible with [Nested].
abstract class SingleChildStatefulWidget extends StatefulWidget
    implements SingleChildWidget {
  /// Creates a widget that has exactly one child widget.
  const SingleChildStatefulWidget({Key? key, Widget? child})
    : _child = child,
      super(key: key);

  final Widget? _child;

  @override
  SingleChildStatefulElement createElement() {
    return SingleChildStatefulElement(this);
  }
}

/// A [State] for [SingleChildStatefulWidget].
///
/// Do not override [build] and instead override [buildWithChild].
abstract class SingleChildState<T extends SingleChildStatefulWidget>
    extends State<T> {
  /// A [build] method that receives an extra `child` parameter.
  ///
  /// This method may be called with a `child` different from the parameter
  /// passed to the constructor of [SingleChildStatelessWidget].
  /// It may also be called again with a different `child`, without this widget
  /// being recreated.
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) => buildWithChild(context, widget._child);
}

/// An [Element] that uses a [SingleChildStatefulWidget] as its configuration.
class SingleChildStatefulElement extends StatefulElement
    with SingleChildWidgetElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildStatefulElement(SingleChildStatefulWidget widget) : super(widget);

  @override
  SingleChildStatefulWidget get widget =>
      super.widget as SingleChildStatefulWidget;

  @override
  SingleChildState<SingleChildStatefulWidget> get state =>
      super.state as SingleChildState<SingleChildStatefulWidget>;

  @override
  Widget build() {
    if (_parent != null) {
      return state.buildWithChild(this, _parent!.injectedChild!);
    }
    return super.build();
  }
}

/// A [SingleChildWidget] that delegates its implementation to a callback.
///
/// It works like [Builder], but is compatible with [Nested].
class SingleChildBuilder extends SingleChildStatelessWidget {
  /// Creates a widget that delegates its build to a callback.
  ///
  /// The [builder] argument must not be null.
  const SingleChildBuilder({Key? key, required this.builder, Widget? child})
    : super(key: key, child: child);

  /// Called to obtain the child widget.
  ///
  /// The `child` parameter may be different from the one parameter passed to
  /// the constructor of [SingleChildBuilder].
  final Widget Function(BuildContext context, Widget? child) builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    return builder(context, child);
  }
}

mixin SingleChildStatelessWidgetMixin
    implements StatelessWidget, SingleChildStatelessWidget {
  Widget? get child;

  @override
  Widget? get _child => child;

  @override
  SingleChildStatelessElement createElement() {
    return SingleChildStatelessElement(this);
  }

  @override
  Widget build(BuildContext context) {
    return buildWithChild(context, child);
  }
}

mixin SingleChildStatefulWidgetMixin on StatefulWidget
    implements SingleChildWidget {
  Widget? get child;

  @override
  _SingleChildStatefulMixinElement createElement() =>
      _SingleChildStatefulMixinElement(this);
}

mixin SingleChildStateMixin<T extends StatefulWidget> on State<T> {
  Widget buildWithChild(BuildContext context, Widget child);

  @override
  Widget build(BuildContext context) {
    return buildWithChild(
      context,
      (widget as SingleChildStatefulWidgetMixin).child!,
    );
  }
}

class _SingleChildStatefulMixinElement extends StatefulElement
    with SingleChildWidgetElementMixin {
  _SingleChildStatefulMixinElement(SingleChildStatefulWidgetMixin widget)
    : super(widget);

  @override
  SingleChildStatefulWidgetMixin get widget =>
      super.widget as SingleChildStatefulWidgetMixin;

  @override
  SingleChildStateMixin<StatefulWidget> get state =>
      super.state as SingleChildStateMixin<StatefulWidget>;

  @override
  Widget build() {
    if (_parent != null) {
      return state.buildWithChild(this, _parent!.injectedChild!);
    }
    return super.build();
  }
}

mixin SingleChildInheritedElementMixin
    on InheritedElement, SingleChildWidgetElementMixin {
  @override
  Widget build() {
    if (_parent != null) {
      return _parent!.injectedChild!;
    }
    return super.build();
  }
}
