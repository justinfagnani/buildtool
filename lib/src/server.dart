// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library server;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:json';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'package:logging/logging.dart';

final Logger _logger = new Logger('server');
Builder builder = new Builder(new Path(BUILD_DIR), new Path('packages/gen'));

Future serverSetup() {
  return _createLogFile();
}

serverMain() {
  _logger.info("startServer");
  var serverSocket = new ServerSocket("127.0.0.1", 0, 0);
  _logger.info("listening on localhost:${serverSocket.port}");
  var server = new HttpServer();

  server.addRequestHandler((req) => req.path == BUILD_URL, _buildHandler);
  server.addRequestHandler((req) => req.path == CLOSE_URL, _closeHandler);
  server.addRequestHandler((req) => req.path == STATUS_URL, _statusHandler);

  server.listenOn(serverSocket);
  _writeLockFile(serverSocket.port).then((int port) {
    stdout.writeString("buildtool server ready\n");
    stdout.writeString("port: ${port}\n");
    stdout.flush();
    if (port != serverSocket.port) {
      _logger.info("Another server already running on port $port.");
      exit(0);
    }
  });
}

void _buildHandler(HttpRequest req, HttpResponse res) {
  readStreamAsString(req.inputStream)
    .catchError((e) {
      _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
      _jsonReply(res, {'status': 'ERROR', 'error': "$e ${e.stackTrace}"});
      return true;
    }).then((str) {
      var data = parse(str);
      builder.build(data['changed'], data['removed'], clean: data['clean'])
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
          _jsonReply(res, data);
        },
        onError: (e) {
          _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
          _jsonReply(res, {'status': 'ERROR', 'error': "$e"});
          throw e;
        });
    });
}

void _closeHandler(HttpRequest req, HttpResponse res) {
  _logger.fine("closing server... ");
  Future.wait([_deleteLockFile(), _closeLogFile()])
      .catchError((e) {
        res.outputStream.onClosed = () {
          _logger.fine("closed");
        };
        _logger.severe("error: $e\nstacktrace: ${e.stackTrace}");
        _jsonReply(res, {'status': 'CLOSED', 'error': "$e"});
        return true;
      }).then((_) {
        res.outputStream.onClosed = () {
          _logger.fine("closed");
        };
        _jsonReply(res, {'status': 'CLOSED'});
      });
}

void _statusHandler(HttpRequest req, HttpResponse res) {
  _jsonReply(res, {'status': 'OK'});
}

void _jsonReply(HttpResponse res, var data) {
  var str = stringify(data);
  res.contentLength = str.length;
  res.headers.contentType = JSON_TYPE;
  res.outputStream.writeString(str);
  res.outputStream.close();
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
Future<int> _writeLockFile(int port) {
  var lockFile = new File(BUILDLOCK_FILE);
  return lockFile.exists().then((exists) {
    var serverPort = port;
    if (exists) {
      return readStreamAsString(lockFile.openInputStream()).then((str) {
        var otherPort;
        try {
          otherPort = int.parse(str);
        } on Error catch(e) {
          // if we can't parse a port, create the lockfile
          return new Future.immediate(true);
        }
        return _pingServer(otherPort).then((responded) {
          if (responded) {
            // make sure we return the other server's port
            port = otherPort;
          }
          // create lockfile if other server didn't respond
          return !responded;
        });
      });
    } else {
      // create lockfile if it doesn't exist
      return new Future.immediate(true);
    }
  }).then((create) {
    if (create) {
      var completer = new Completer();
      var os = lockFile.openOutputStream(FileMode.WRITE);
      os.writeString("$port");
      os.flush();
      os.onNoPendingWrites = () => completer.complete(port);
      return completer.future;
    } else {
      return new Future.immediate(port);
    }
  });
}

Future _deleteLockFile() {
  return new File(BUILDLOCK_FILE).delete();
}

OutputStream _logStream;

Future _createLogFile() {
  return new File(LOG_FILE).create().then((log) {
    _logStream = log.openOutputStream(FileMode.APPEND);
    Logger.root.level = Level.FINE;
    Logger.root.on.record.add((LogRecord r) {
      var m = "${r.time} ${r.loggerName} ${r.level} ${r.message}\n";
      _logStream.writeString(m);
      stdout.writeString(m);
      stdout.flush();
    });
    return true;
  });
}

Future _closeLogFile() {
  if (_logStream != null) {
    var completer = new Completer();
    _logStream.close();
    _logStream.onClosed = () => completer.complete(null);
    return completer.future;
  } else {
    return new Future.immediate(null);
  }
}

Future<bool> _pingServer(int port) {
  var completer = new Completer();
  var client = new HttpClient();
  var conn = client.post("localhost", port, STATUS_URL)
    ..onRequest = (req) {
      req.outputStream.close();
    }
    ..onResponse = (res) {
      readStreamAsString(res.inputStream).then((str) {
        var data = parse(str);
        completer.complete((data is Map) && (data.containsKey('status')
            && data['status'] == 'OK'));
      });
    }
    ..onError = (e) {
      completer.complete(false);
    };
  return completer.future;
}
