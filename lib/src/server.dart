// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library server;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:json';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/util/io.dart';
import 'package:logging/logging.dart';
import 'package:route/server.dart';

final Logger _logger = new Logger('server');

typedef void Config(Builder builder);

class Server {
  final Builder _builder;
  final Config _configClosure;

  Server(this._configClosure, Path baseDir, {Builder builder})
      : _builder = (builder != null)
            ? builder
            : new Builder(new Path(BUILD_DIR), new Path(GEN_DIR),
                  new Path(DEPLOY_DIR), basePath: baseDir);

  Future<bool> start() {
    return _createLogFile().then((_) {
      _logger.info("Starting server");
      return HttpServer.bind("127.0.0.1", 0, 0).then((server) {
        var router = new Router(server);
        router.serve(BUILD_URL).listen(_buildHandler);
        router.serve(CLOSE_URL).listen(_closeHandler);
        router.serve(STATUS_URL).listen(_statusHandler);

        return _writeLockFile(_builder.basePath, server.port)
          .then((int port) {
            stdout.addString("buildtool server ready\n");
            stdout.addString("port: ${port}\n");
            if (port != server.port) {
              _logger.info("Another server already running on port $port.");
              server.close();
              return false;
            }
            _configClosure(_builder);
            return true;
          });
      });
    });
  }

  void _buildHandler(HttpRequest req) {
    req.transform(new StringDecoder()).toList()
      .catchError((e) {
        _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
        _jsonReply(req, {'status': 'ERROR', 'error': "$e ${e.stackTrace}"});
        return true;
      }).then((str) {
        var data = parse(str.join(''));
        _logger.info("build command received data: $data");

        _builder.build(data['changed'], data['removed'], clean: data['clean'],
            deploy: data['deploy'])
          .then((BuildResult result) {
            var mappings = [];
            for (var source in result.mappings.keys) {
              mappings.add({'from': source, 'to': result.mappings[source]});
            }
            var data = {
              'status': 'OK',
              'messages': result.messages,
              'mappings': mappings,
            };
            _logger.fine("data: $data");
            _jsonReply(req, data);
          },
          onError: (e) {
            _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
            _jsonReply(req, {'status': 'ERROR', 'error': "$e"});
            throw e;
          });
      });
  }

  void _closeHandler(HttpRequest req) {
    _logger.fine("closing server... ");
    Future.wait([_deleteLockFile(), _closeLogFile()])
        .catchError((e) {
          _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
          _jsonReply(req, {'status': 'CLOSED', 'error': "$e"});
          return true;
        }).then((_) {
          req.response.done.then((_) {
            _logger.fine("closed");
          });
          _jsonReply(req, {'status': 'CLOSED'});
        });
  }

  void _statusHandler(HttpRequest req) {
    _jsonReply(req, {'status': 'OK'});
  }

  void _jsonReply(HttpRequest req, var data) {
    var str = stringify(data);
    req.response
      ..contentLength = str.length
      ..headers.contentType = JSON_TYPE
      ..addString(str)
      ..close();
  }

  /**
   * Attempts to write a lock file containing [port].
   *
   * If the lock file doesn't exist, it's created and the value passed to [port]
   * is returned in the Future.
   *
   * If the lock file already exists, tries to contact a server at the port in
   * the lock file. If the server is alive, returns the port from the lock file.
   * If the server isn't alive, the lock file is overwritten with [port].
   *
   * Note: This isn't a failsafe locking mechanism. There are several race
   * conditions present, but Dart needs some kind of mutex mechanism to solve
   * them.
   */
  Future<int> _writeLockFile(Path baseDir, int port) {
    var lockFile = new File.fromPath(baseDir.append(BUILDLOCK_FILE));
    var serverPort = port;
    if (lockFile.existsSync()) {
      var contents = lockFile.readAsStringSync();
      return new Future.of(() => int.parse(contents))
        .then((int otherPort) {
          return _pingServer(otherPort).then((responded) {
          if (responded) {
            // make sure we return the other server's port
            return otherPort;
          }
          // create lockfile if other server didn't respond
          _createLockFile(baseDir, port);
          return port;
        });
      }).catchError((e) {
        _createLockFile(baseDir, port);
        return new Future.immediate(port);
      });
    } else {
      _createLockFile(baseDir, port);
      return new Future.immediate(port);
    }
  }

  void _createLockFile(Path baseDir, int port) {
    new File.fromPath(baseDir.append(BUILDLOCK_FILE))
        .writeAsStringSync("$port", mode: FileMode.WRITE);
  }

  Future _deleteLockFile() {
    return new File(BUILDLOCK_FILE).delete();
  }

  IOSink _logSink;

  Future _createLogFile() {
    return new File(LOG_FILE).create().then((log) {
      _logSink = log.openWrite(FileMode.APPEND);
      Logger.root.level = Level.FINE;
      Logger.root.onRecord.listen((LogRecord r) {
        var m = "${r.time} ${r.loggerName} ${r.level} ${r.message}\n";
        _logSink.addString(m);
        stdout.addString(m);
      });
      return true;
    });
  }

  Future _closeLogFile() =>
      _logSink == null ? new Future.immediate(null) : (_logSink..close()).done;

  /**
   * Pings another buildtool server to see if it's running. Returns [:true:] if
   * the server responds with a status of 'OK'.
   */
  Future<bool> _pingServer(int port) =>
    new HttpClient().post("localhost", port, STATUS_URL)
      .then((req) => req.response)
      .then(byteStreamToString)
      .then(parse)
      .then((data) =>
          data is Map && data.containsKey('status') && data['status'] == 'OK');
}
