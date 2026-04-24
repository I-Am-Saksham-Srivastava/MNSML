import 'package:build/build.dart';
import './codegen.dart';
import 'package:source_gen/source_gen.dart';

Builder storeGenerator(BuilderOptions options) =>
    SharedPartBuilder([StoreGenerator(options)], 'store_generator');
