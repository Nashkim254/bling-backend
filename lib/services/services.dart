import 'package:bling/services/firebase_service.dart';
import 'package:get_it/get_it.dart';

export 'package:bling/services/services.dart';


void setup() {
  GetIt.instance.registerSingleton<FirebaseService>(FirebaseService());
}