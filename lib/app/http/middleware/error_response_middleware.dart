import 'package:vania/vania.dart';

class ErrorResponseMiddleware extends Middleware {
  @override
  handle(Request req) async {
    final contentType = (req.header('content-type') ?? '').toLowerCase();
    if (contentType.isNotEmpty && !contentType.contains('application/json')) {
      abort(400, 'Your request is not valid');
    }
  }
}
