import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/settings/settings_detail_scaffold.dart';
import 'package:anikumo/bean/widget/error_widget.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('Anikumo'),
      body: GeneralErrorWidget(
        title: '无法打开页面',
        errMsg: message,
        actions: [
          StateActionButton(
            onPressed: () => context.navigate('/tab/popular/'),
            icon: AnikumoIcons.home_outlined,
            text: '返回首页',
          ),
        ],
      ),
    );
  }
}
