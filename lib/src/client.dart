// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client;

import 'dart:async';
import 'dart:io';
import 'dart:json';
import 'package:args/args.dart';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger('client');

void clientMain(ArgResults args) {
  var quit = args['quit'];
  if (quit == true) {
    _logger.fine("quitting server");
    _getServerPort().then((port) {
      if (port != null) {
        _sendCloseCommand(port).then((s) {
        });
      } else {
        _logger.severe("no server to quit");
      }
    });
  } else {
    var changedFiles = args['changed'];
    var filteredFiles = changedFiles.where(isValidInputFile);
    if (args['machine'] && filteredFiles.isEmpty) {
      _logger.info("no changed files");
    } else {
      _getServerPort().then((port) {
        if (port != null) {
          _sendBuildCommand(port, filteredFiles, args['clean'])
            .then((Map result) {
              List<Map<String, String>> mappingList = result['mappings'];
              for (var mapping in mappingList) {
                var message = stringify([{
                  'method': 'mapping',
                  'params': {
                    'from': mapping['from'],
                    'to': mapping['to'],
                  },
                }]);
                // write message for the Editor to receive
                stdout.writeString("$message\n");
              }
            });
        } else {
          _logger.severe("Error starting buildtool server.");
          exitCode = 1;
        }
      });
    }
  }
}

final int _CONNECTION_REFUSED = 61;

Future _sendCloseCommand(int port) {
  return _sendJsonCommand(port, CLOSE_URL);
}

/** Sends a JSON-formatted build command to the build server via HTTP POST. */
Future<Map> _sendBuildCommand(
    int port,
    List<String> changedFiles,
    bool cleanBuild) {
  return _sendJsonCommand(port, BUILD_URL, data: {
    'changed': changedFiles,
    'removed': [],
    'clean': cleanBuild,
  });
}

/**
 * Sends a POST request to the server at path [path] with a JSON
 * representation of [data] as the request body. The response is parsed as JSON
 * and returned via a Future
 */
Future<dynamic> _sendJsonCommand(int port, String path, {var data,
    bool isRetry: false}) {
  var completer = new Completer();
  var client = new HttpClient();
  var conn = client.post("localhost", port, path)
    ..onRequest = (req) {
      req.headers.contentType = JSON_TYPE;
      if (data != null) {
        var json = stringify(data);
        req.contentLength = json.length;
        req.outputStream.writeString(json);
      }
      req.outputStream.close();
    }
    ..onResponse = (res) {
      readStreamAsString(res.inputStream)
        .catchError((e) {
          completer.completeError(e);
          client.shutdown();
          return true;
        })
        .then((str) {
          var response = parse(str);
          client.shutdown();
          completer.complete(response);
        });
    }
    ..onError = (e) {
      _logger.severe("error: $e");
      client.shutdown();
      if (e is SocketIOException &&
          e.osError.errorCode == _CONNECTION_REFUSED &&
          !isRetry) {
        //restart server
        _logger.fine("restarting server");
        _startServer()
          .catchError((e) {
            completer.completeError(e);
            return true;
          })
          .then((port) {
            _logger.fine("restarted server on port $port");
            _sendJsonCommand(port, path, data: data, isRetry: true)
              .catchError((e) {
                completer.completeError(e);
                return true;
              })
              .then((v) => completer.complete(v));
          });
      } else {
        _logger.severe("exception: $e");
        completer.completeError(e);
      }
    };
  return completer.future;
}

/** Returns the port of the running builtool server, or starts a new server. */
Future<int> _getServerPort() {
  var completer = new Completer();
  var lockFile = new File('.buildlock');
  lockFile.exists().then((exists) {
    if (exists) {
      var sb = new StringBuffer();
      var sis = new StringInputStream(lockFile.openInputStream());
      sis
        ..onData = () {
          sb.add(sis.read());
        }
        ..onClosed = () {
          try {
            var port = int.parse(sb.toString());
            _logger.fine("server already running onport: $port");
            completer.complete(port);
          } on Error catch (e) {
            completer.completeError(e);
          }
        };
    } else {
      _startServer().then((v) => completer.complete(v));
    }
  });
  return completer.future;
}

Future<int> _startServer() {
  var completer = new Completer();
  var vmExecutable = new Options().executable;
  Process.start(vmExecutable, ["build.dart", "--server"]).then((process) {
    var sis = new StringInputStream(process.stdout);
    sis.onData = () {
      var line = sis.readLine();
      _logger.fine(line);
      if (line.startsWith("port: ")) {
        var port = int.parse(line.substring("port: ".length));
        completer.complete(port);
      }
    };
  });
  return completer.future;
}