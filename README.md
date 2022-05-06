# HydraDart
Hydra for Dartlang - A light-weight library for building distributed applications such as microservices.

![](HydraDart.png)

## Example

In this example HydraDart uses Dart Shelf to allow a Dart service to be discoverable within a Docker Swarm or Kubernetes cluster.

```dart
import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import './hydra.dart';

// Configure routes.
final _router = Router()
  ..get('/v1/dart', _rootHandler)
  ..get('/v1/dart/echo/<message>', _echoHandler);

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

Response _echoHandler(Request request) {
  final message = params(request, 'message');
  return Response.ok('$message\n');
}

void main(List<String> args) async {
  var hydra = Hydra();
  hydra.addRoute('/v1/dart', 'get');
  hydra.addRoute('/v1/dart/echo/:message', 'get');

  // Load configuration file
  File configFile = File('./configs/dart-svcs-config.json'); // (1)
  Future<String> futureContent = configFile.readAsString();
  futureContent.then((config) async {
    Map<String, dynamic> configMap = jsonDecode(config);

    // Use any available host or container IP (usually `0.0.0.0`).
    final ip = InternetAddress.anyIPv4;

    // Configure a pipeline that logs requests.
    final _handler =
        Pipeline().addMiddleware(logRequests()).addHandler(_router);

    // For running in containers, we respect the PORT environment variable.
    final port = configMap['hydra']['servicePort'];

    final server = await serve(_handler, ip, port);
    print('Server listening on port ${server.port}');

    hydra.init(configMap);
  });
}
```

In the example above our server application loads a `dart-svcs-config.json` file and passes it along to the `hydra.init()` member function.

```json
{
  "hydra": {
    "serviceName": "dart-svcs",
    "serviceIP": "",
    "servicePort": 7134,
    "serviceType": "test",
    "serviceDescription": "Dart experimental service",
    "plugins": {
      "hydraLogger": {
        "logToConsole": true,
        "onlyLogLocally": false
      }
    },
    "redis": {
      "urlxxx": "redis://redis:6379/15",
      "host": "redis",
      "port": 6379,
      "db": 15
    }
  }
}
```