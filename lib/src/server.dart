// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library server;

import 'dart:io';
import 'dart:isolate';
import 'dart:json';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'package:logging/logging.dart';

final Logger _logger = new Logger('server');
Builder builder = new Builder(new Path('out'), new Path('packages/gen'));

serverMain() {
  _createLogFile().then((_) {
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
      stdout.close();
      if (port != serverSocket.port) {
        _logger.info("Another server already running on port $port.");
        exit(0);
      }
    });
  });
}

void _buildHandler(HttpRequest req, HttpResponse res) {
  readStreamAsString(req.inputStream).then((str) {
    var data = JSON.parse(str);
    builder.build(data['changed'], data['removed'], data['clean']);
    res.contentLength = 0;
    res.outputStream.close();    
  });
}

void _closeHandler(HttpRequest req, HttpResponse res) {
  Futures.wait([_deleteLockFile(), _closeLogFile()]).then((_) {
    res.contentLength = 0;
    res.outputStream.close();
    exit(0);
  });
}

void _statusHandler(HttpRequest req, HttpResponse res) {
  var data = {'status': 'OK'};
  var str = JSON.stringify(data);
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
  return lockFile.exists().chain((exists) {
    var serverPort = port;
    if (exists) {
      return readStreamAsString(lockFile.openInputStream()).chain((str) {
        var otherPort;
        try {
          otherPort = int.parse(str);
        } on Error catch(e) {
          // if we can't parse a port, create the lockfile
          return new Future.immediate(true);
        }
        return _pingServer(otherPort).transform((responded) {
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
  }).chain((create) {
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

var _logStream;

Future _createLogFile() {
  return new File(BUILDLOG_FILE).create().transform((log) {
    _logStream = log.openOutputStream(FileMode.APPEND);
    Logger.root.on.record.add((LogRecord r) {
      var m = "${r.time} ${r.level} ${r.message}\n";
      _logStream.writeString(m);
      print(m);
    });
    return true;
  });
}

Future _closeLogFile() {
  if (_logStream != null) {
    return _logStream.close();
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
        var data = JSON.parse(str);
        completer.complete((data is Map) && (data.containsKey('status') 
            && data['status'] == 'OK'));        
      });
    }
    ..onError = (e) {
      completer.complete(false);
    };
  return completer.future;
}
