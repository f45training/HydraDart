# HydraDart
Hydra for [Dartlang](https://dart.dev) - A light-weight library for building distributed applications such as microservices.

![](HydraDart.png)

## Example

In this example HydraDart uses [Dart Shelf](https://pub.dev/packages/shelf) and [Dart Self Router](https://pub.dev/packages/shelf_router) to allow a Dart service to be discoverable within a Docker Swarm or Kubernetes cluster.

```dart
import 'dart:io';
import 'dart:convert';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import './hydra.dart';

class API {
  helloHandler(Request request) {
    return Response.ok('hello-world');
  }

  userHandler(Request request, String user) {
    return Response.ok('hello $user');
  }
}

void main(List<String> args) async {
  var hydra = Hydra();
  var router = Router();
  var api = API();

  hydra.bindRouter(router);
  hydra.addRoute('/v1/dart', 'get', api.helloHandler);
  hydra.addRoute('/v1/dart/user/<user>', 'get', api.userHandler);

  // Load configuration file
  File configFile = File('./configs/dart-svcs-config.json');
  Future<String> futureContent = configFile.readAsString();
  futureContent.then((config) async {
    Map<String, dynamic> configMap = jsonDecode(config);

    // Use any available host or container IP (usually `0.0.0.0`).
    final ip = InternetAddress.anyIPv4;

    // Configure a pipeline that logs requests.
    final routerHandler =
        Pipeline().addMiddleware(logRequests()).addHandler(router);

    // For running in containers, we respect the PORT environment variable.
    final port = configMap['hydra']['servicePort'];

    final server = await io.serve(routerHandler, ip, port);
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