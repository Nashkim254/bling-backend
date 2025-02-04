import 'package:bling/services/services.dart';
import 'package:vania/vania.dart';
import 'package:bling/config/app.dart';

void main() async {
  setup();
  Application().initialize(config: config);
}
