import 'package:flutter/widgets.dart';

import 'data/geo.dart';
import 'data/repository.dart';
import 'security/admin_auth.dart';
import 'state/settings.dart';

/// Dependency container for the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.repo,
    required this.admin,
    required this.version,
    required this.geo,
    required super.child,
  });

  final Settings settings;
  final PriceRepository repo;
  final AdminAuth admin;
  final String version;
  final GeoService geo;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}
