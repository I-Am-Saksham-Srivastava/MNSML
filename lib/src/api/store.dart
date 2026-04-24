import 'package:mnsml/mnsml.dart';

/// The `Store` mixin is primarily meant for code-generation and used as part of the
/// `mnsml_codegen` package.
///
/// A class using this mixin is considered a mnsml store and `mnsml_codegen`
/// weaves the code needed to simplify the usage of mnsml. It will detect annotations like
/// `@observables`, `@computed` and `@action` and generate the code needed to support these behaviors.
mixin Store {
  /// Override this method to use a custom context.
  ReactiveContext get context => mainContext;
}
