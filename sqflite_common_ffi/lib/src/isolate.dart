import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:sqflite_common_ffi/src/method_call.dart';
import 'package:sqflite_common_ffi/src/sqflite_ffi_exception.dart';

import 'sqflite_ffi_impl.dart';

bool _debug = false; // devWarning(true); // false;

/// Sqflite isolate.
class SqfliteIsolate {
  /// Sqflite isolate.
  SqfliteIsolate({@required this.sendPort});

  /// Our send port.
  final SendPort sendPort;

  /// Handle a method call.
  Future<dynamic> handle(FfiMethodCall methodCall) async {
    var recvPort = ReceivePort();
    var map = <String, dynamic>{
      'method': methodCall.method,
      'arguments': methodCall.arguments,
    };
    if (_debug) {
      print('send $map');
    }
    map['sendPort'] = recvPort.sendPort;

    sendPort.send(map);
    var response = await recvPort.first;
    if (_debug) {
      print('recv $response');
    }
    if (response is Map) {
      var error = response['error'];
      if (error is Map) {
        throw SqfliteFfiException(
            code: error['code'] as String,
            message: error['message'] as String,
            details: (error['details'] as Map)?.cast<String, dynamic>());
      }
      return response['result'];
    }
    return null;
  }
}

/// Create an isolate.
Future<SqfliteIsolate> createIsolate() async {
  // create a long-lived port for receiving messages
  var ourFirstReceivePort = ReceivePort();

  // spawn the isolate with an initial sendPort.
  await Isolate.spawn(_isolate, ourFirstReceivePort.sendPort);

  // the isolate sends us its SendPort as its first message.
  // this lets us communicate with it. we’ll always use this port to
  // send it messages.
  var sendPort = (await ourFirstReceivePort.first) as SendPort;

  return SqfliteIsolate(sendPort: sendPort);
}

/// The isolate
Future _isolate(SendPort sendPort) async {
  // open our receive port. this is like turning on
  // our cellphone.
  var ourReceivePort = ReceivePort();

  // tell whoever created us what port they can reach us on
  // (like giving them our phone number)
  sendPort.send(ourReceivePort.sendPort);

  // listen for text messages that are sent to us,
  // and respond to them with this algorithm
  await for (var msg in ourReceivePort) {
    // devPrint(msg);
    if (msg is Map) {
      var sendPort = msg['sendPort'];
      if (sendPort is SendPort) {
        var method = msg['method'] as String;
        if (method != null) {
          try {
            var arguments = msg['arguments'];
            var methodCall = FfiMethodCall(method, arguments);
            var result = await methodCall.handleImpl();
            sendPort.send({'result': result});
          } catch (e) {
            var error = <String, dynamic>{};
            if (e is SqfliteFfiException) {
              error['code'] = e.code;
              error['details'] = e.details;
              error['message'] = e.message;
            } else {
              // should not happen
              error['message'] = e.toString();
            }
            sendPort.send({'error': error});
          }
        }
      }
    }
  }
}
