// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client;

import 'package:args/args.dart';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'dart:io';
import 'dart:json';

void clientMain(ArgResults args) {
  var quit = args['quit'];
  if (quit == true) {
    print("quitting server");
    _getServerPort().then((port) {
      if (port != null) {
        _sendCloseCommand(port).then((s) {
          exit(0);
        });
      } else {
        print("no server to quit");
        exit(0);
      }
    });
  } else {
    var changedFiles = args['changed'];
    var filteredFiles = changedFiles.filter(isValidInputFile);
    if (args['machine'] && filteredFiles.isEmpty) {
      print("no changed files");
      exit(0);
    }
    _getServerPort().then((port) {
      if (port != null) {
        _sendBuildCommand(port, filteredFiles, args['clean']);
      } else {
        print("Error starting buildtool server.");
        exit(1);
      }
    });
  }
}

final int _CONNECTION_REFUSED = 61;

Future _sendCloseCommand(int port) {
  return _sendJsonCommand(port, CLOSE_URL);
}

/** Sends a JSON-formatted build command to the build server via HTTP POST. */
Future _sendBuildCommand(int port, List<String> changedFiles, bool cleanBuild) {
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
Future _sendJsonCommand(int port, String path, {var data, 
    bool isRetry: false}) {
  var completer = new Completer();
  var client = new HttpClient();
  var conn = client.post("localhost", port, path)
    ..onRequest = (req) {
      req.headers.contentType = JSON_TYPE;
      if (data != null) {
        var json = JSON.stringify(data);
        req.contentLength = json.length;
        req.outputStream.writeString(json);
      }
      req.outputStream.close();
    }
    ..onResponse = (res) {
      readStreamAsString(res.inputStream)
        ..handleException((e) {
          completer.completeException(e);
          return true;
        })
        ..then((str) {
          var response = JSON.parse(str);
          completer.complete(response);
        });
    }
    ..onError = (e) {
      print("error: $e");
      if (e is SocketIOException && 
          e.osError.errorCode == _CONNECTION_REFUSED &&
          !isRetry) {
        //restart server
        print("restarting server");
        _startServer()
          ..handleException((e) {
            completer.completeException(e);
            return true;
          })
          ..then((port) {
            print("restarted server on port $port");
            _sendJsonCommand(port, path, data: data, isRetry: true)
              ..handleException((e) {
                completer.completeException(e);
                return true;
              })
              ..then(completer.complete);
          });
      } else {
        completer.completeException(e);
      }
    };
  return completer.future;
}

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
            print("server already running onport: $port");
            completer.complete(port);
          } on Error catch (e) {
            completer.completeException(e);
          }
        };
    } else { 
      _startServer().then(completer.complete);
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
      print(line);
      if (line.startsWith("port: ")) {
        var port = int.parse(line.substring("port: ".length));
        completer.complete(port);
      }
    };
  });
  return completer.future;
}