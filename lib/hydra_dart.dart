import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:redis/redis.dart';
import 'package:uuid/uuid.dart';
import 'package:shelf_router/shelf_router.dart';

/// HydraPresence is used for JSON conversion
///
class HydraPresence {
  String serviceName;
  String serviceDescription;
  String version;
  String instanceID;
  int processID;
  String ip;
  int port;
  String hostName;
  String updatedOn;
  HydraPresence(
      this.serviceName,
      this.serviceDescription,
      this.version,
      this.instanceID,
      this.processID,
      this.ip,
      this.port,
      this.hostName,
      this.updatedOn);
  Map toJson() => {
        'serviceName': serviceName,
        'serviceDescription': serviceDescription,
        'version': version,
        'instanceID': instanceID,
        'processID': processID,
        'ip': ip,
        'port': port,
        'hostName': hostName,
        'updatedOn': updatedOn
      };
}

/// HydraMemory is used with HydraHealth to define memory values
///
class HydraMemory {
  int rss;
  int heapTotal;
  int heapUsed;
  int ext;
  int arrayBuffers;
  HydraMemory(
      this.rss, this.heapTotal, this.heapUsed, this.ext, this.arrayBuffers);
  Map toJson() => {
        'rss': rss,
        'heapTotal': heapTotal,
        'heapUsed': heapUsed,
        'external': ext,
        'arrayBuffers': arrayBuffers
      };
}

/// HydraHealth is used to generate the JSON for serialization to
/// Redis
///
class HydraHealth {
  String updatedOn;
  String serviceName;
  String instanceID;
  String hostName;
  String sampledOn;
  int processID;
  String architecture;
  String platform;
  String nodeVersion;
  HydraMemory hydraMemory;
  HydraHealth(
      this.updatedOn,
      this.serviceName,
      this.instanceID,
      this.hostName,
      this.sampledOn,
      this.processID,
      this.architecture,
      this.platform,
      this.nodeVersion,
      this.hydraMemory);
  Map toJson() => {
        'updatedOn': updatedOn,
        'serviceName': serviceName,
        'instanceID': instanceID,
        'hostName': hostName,
        'sampledOn': sampledOn,
        'processID': processID,
        'architecture': architecture,
        'platform': platform,
        'nodeVersion': nodeVersion,
        'memory': hydraMemory,
        'uptimeSeconds': 0 // current time - uptime
      };
}

/// UMF
///
class UMF {
  String _to = '';
  String _frm = '';
  String _mid = '';
  String _ts = '';
  String _bdy = '';

  UMF(String to, String frm, String bdy) {
    _to = to;
    _frm = frm;
    _mid = (Uuid()).v4();
    _ts = timeStamp();
    _bdy = bdy;
  }
  toJsonString() {
    String json = '''{
      "to": "$_to",
      "frm": "$_frm",
      "mid": "$_mid",
      "ts": "$_ts",
      "bdy": $_bdy
    }''';
    return jsonEncode(jsonDecode(json));
  }
}

/// timeStamp
///
timeStamp() {
  String s = DateTime.now().toUtc().toIso8601String();
  return '${s.substring(0, s.length - 4)}Z';
}

/// Hydra is the main module used to support microservices
/// functionality using Redis
///
class Hydra {
  static const int oneSecond = 1;
  static const int oneWeekInSeconds = 604800;
  static const int presenceUpdateInterval = oneSecond;
  static const int heatlhUpdateInterval = oneSecond * 5;
  static const int keyExperationTTL = oneSecond * 3;
  static const String redisPreKey = 'hydra:service';
  static const String mcMessageKey = 'hydra:service:mc';
  late RedisConnection redis;
  late int redisDB;
  late Command redisCommand;
  late Timer periodicTimer;
  late String serverInstanceID;
  int healthTick = 0;
  late String serviceName;
  late String serviceDescription;
  late String hostName;
  late int processID;
  late String ip;
  late int port;
  late String version = '0.0.1';

  late Router routerInstance;
  List<String> hydraRoutes = [];

  /// init is used to initialize the Hydra module
  /// init accepts a map which is created from reading a JSON based
  /// configuration file
  ///
  init(Map<String, dynamic> configMap) async {
    ip = await getLocalIP();
    port = configMap['hydra']['servicePort'];
    hostName = Platform.localHostname;
    processID = pid;
    serviceName = configMap['hydra']['serviceName'];
    serviceDescription = configMap['hydra']['serviceDescription'];
    var uuid = Uuid();
    serverInstanceID = uuid.v4().replaceAll(RegExp('-'), '');

    periodicTimer =
        Timer.periodic(const Duration(seconds: oneSecond), heartBeat);

    redisDB = configMap['hydra']['redis']['db'];
    redis = RedisConnection();
    redisCommand = await redis.connect(configMap['hydra']['redis']['host'],
        configMap['hydra']['redis']['port']);
    await registerRoutes();
  }

  /// shutdown
  ///
  shutdown() {
    periodicTimer.cancel();
    redis.close();
  }

  /// heartBeat
  ///
  heartBeat(timer) {
    healthTick++;
    if (healthTick == heatlhUpdateInterval) {
      healthTick = 0;
      redisCommand.send_object(['SELECT', redisDB]).then((var response) {
        if (response == 'OK') {
          redisCommand.send_object([
            'SETEX',
            '$redisPreKey:$serviceName:$serverInstanceID:health',
            keyExperationTTL,
            health()
          ]);
        }
      });
    }

    redisCommand.send_object(['SELECT', redisDB]).then((var response) {
      if (response == 'OK') {
        redisCommand.send_object([
          'SETEX',
          '$redisPreKey:$serviceName:$serverInstanceID:presence',
          keyExperationTTL,
          serverInstanceID
        ]);
        redisCommand.send_object(
            ['HSET', '$redisPreKey:nodes', serverInstanceID, presence()]);
      }
    });
  }

  /// presence
  ///
  presence() {
    return jsonEncode(HydraPresence(serviceName, serviceDescription, version,
        serverInstanceID, processID, ip, port, hostName, timeStamp()));
  }

  /// health
  ///
  health() {
    HydraMemory memory = HydraMemory(0, 0, 0, 0, 0);
    String ts = timeStamp();
    return jsonEncode(HydraHealth(ts, serviceName, serverInstanceID, hostName,
        ts, pid, 'dart', 'linux', version, memory));
  }

  /// getLocalIP
  ///
  Future getLocalIP() async {
    List<String> ips = [];
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type.name == 'IPv4' && !addr.isLoopback) {
          if (!addr.address.startsWith('172.')) {
            ips.insert(0, addr.address);
          }
        }
      }
    }
    return ips[0];
  }

  /// flushRoutes
  ///
  flushRoutes() async {
    await redisCommand.send_object(['SELECT', redisDB]).then((var response) {
      if (response == 'OK') {
        redisCommand.send_object(
            ['DEL', '$redisPreKey:$serviceName:$serverInstanceID:routes']);
      }
    });
  }

  /// bindRouter
  ///
  bindRouter(Router router) {
    routerInstance = router;
  }

  /// addRoute
  ///
  addRoute(String path, String method, Function handler) {
    switch (method) {
      case 'get':
        routerInstance.get(path, handler);
        return;
      case 'post':
        routerInstance.post(path, handler);
        break;
    }
    var transformedPath = path.replaceAll('<', ':').replaceAll('>', '');
    hydraRoutes.insert(0, '[$method]$transformedPath');
  }

  /// registerRoutes
  ///
  registerRoutes() async {
    await flushRoutes();
    addRoute('/$serviceName', 'get', () => {});
    addRoute('/$serviceName/', 'get', () => {});
    addRoute('/$serviceName/:rest', 'get', () => {});

    UMF umf = UMF('hydra-router:/refresh', '$serviceName:/', '''
      {
        "action": "refresh",
        "serviceName": "$serviceName"
      }
    ''');

    await redisCommand.send_object(['SELECT', redisDB]).then((var response) {
      if (response == 'OK') {
        for (final route in hydraRoutes) {
          redisCommand.send_object(
              ['SADD', '$redisPreKey:$serviceName:service:routes', route]);
        }
        redisCommand.send_object(
            ['PUBLISH', '$mcMessageKey:hydra-router', umf.toJsonString()]);
      }
    });
  }
}
