import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/core_module.dart';
import 'package:anikumo/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
