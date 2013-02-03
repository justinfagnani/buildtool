// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client;

import 'dart:async';
import 'dart:io';
import 'dart:json';
import 'dart:uri';
import 'package:args/args.dart';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

Logger _logger = new Logger('client');

typedef http.Client HttpClientFactory();
typedef Future<Process> ScriptRunner(String file);

_defaultHttpClientFactory() => new http.Client();

_defaultRunScript(String file) {
  var vmExecutable = new Options().executable;
  return Process.start(vmExecutable, [file]);
}

Future<bool> clientMain(ArgResults args) =>
  new ClientStarter(args).run();

/**
 * Client to a BuildServer.
 */
class BuildClient {
  int port;

  final bool machine;
  final bool clean;
  final List<String> changedFiles;
  final List<String> removedFiles;

  final HttpClientFactory httpClientFactory;
  final OutputStream _outputStream;
  var _connectionErrorHandler;

  BuildClient(
    this.port,
    { this.machine: false,
    this.clean: false,
    this.changedFiles: const [],
    this.removedFiles: const [],
    OutputStream outputStream,
    this.httpClientFactory: _defaultHttpClientFactory})
      : _outputStream = (outputStream == null) ? stdout : outputStream {

    if (port == null) {
      throw new ArgumentError("must specifiy a valid TCP port: $port");
    }
  }

  /**
   * Set an error handler for errors that occur when communicating with the
   * build server. If the handler returns a value, then the client should
   * retry using the value as the new port, otherwise the client returns an
   * error.
   */
  void set onConnectionError(Future<int> handler(error)) {
    _connectionErrorHandler = handler;
  }

  Future<bool> quit() {
    _logger.fine("Quit...");
    return _sendCloseCommand();
  }

  Future<bool> build() {
    _logger.info("Build...");
    var filteredFiles = changedFiles.where(isValidInputFile).toList();
    if (machine && filteredFiles.isEmpty) {
      _logger.info("no changed files");
      return new Future.immediate(true);
    } else {
      return _sendBuildCommand(filteredFiles, clean).then((Map result) {
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
          _outputStream.writeString("$message\n");
          _outputStream.flush();
          return true;
        }
      });
    }
  }

  Future _sendCloseCommand() {
    return _sendJsonCommand(CLOSE_URL);
  }

  /** Sends a JSON-formatted build command to the build server via HTTP POST. */
  Future<Map> _sendBuildCommand(
      Iterable<String> changedFiles,
      bool cleanBuild) {
    return _sendJsonCommand(BUILD_URL, data: {
      'changed': changedFiles.toList(),
      'removed': [],
      'clean': cleanBuild,
    });
  }

  /**
   * Sends a POST request to the server at path [path] with a JSON
   * representation of [data] as the request body. The response is parsed as
   * JSON and returned via a Future
   */
  Future<dynamic> _sendJsonCommand(String path, {Object data}) {
    http.Client client = httpClientFactory();

    // Setup the request
    var uri = new Uri.fromComponents(scheme: 'http', domain: 'localhost',
        path: path, port: port);
    var request = new http.Request('POST', uri);
    request.headers[HttpHeaders.CONTENT_TYPE] = JSON_TYPE.toString();
    if (data != null) {
      request.body = stringify(data);
    }

    // Send request and handle response
    return client.send(request).then((http.StreamedResponse response) {
      return response.stream.bytesToString().then((body) {
        return parse(body);
      });
    }).catchError((e) {
      _logger.severe("error: $e");
      client.close();
      // Call the error handler and possibly retry the request
      if (_connectionErrorHandler != null) {
        var future = _connectionErrorHandler(e);
        if (future != null) {
          return future.then((int newPort) {
            if (newPort != null) {
              port = newPort;
              return _sendJsonCommand(path, data: data);
            } else {
              _logger.severe("exception: $e");
              throw e;
            }
          });
        }
      } else {
        _logger.severe("exception: $e");
        throw e;
      }
    });
  }
}

final int _CONNECTION_REFUSED = 61;

class ClientStarter {
  final ScriptRunner _runScript;
  final ArgResults args;

 ClientStarter(ArgResults this.args, {
    ScriptRunner this._runScript: _defaultRunScript});

  Future<bool> run() {
    int retryCount = 0;
    return _getServerPort().then((port) {
      var client = new BuildClient(
          port,
          machine: args['machine'],
          clean: args['clean'],
          changedFiles: args['changed'],
          removedFiles: args['removed']);
      client.onConnectionError = (e) {
        if (e is SocketIOException &&
            e.osError.errorCode == _CONNECTION_REFUSED &&
            retryCount < 1) {
          return _startServer().then((port) {
            _logger.fine("restarted server on port $port");
            return port;
          });
        }
      };
      if (args['quit']) {
        return client.quit();
      } else {
        return client.build();
      }
    });
  }

  /**
   * Returns the port of the running builtool server, or starts a new server.
   */
  Future<int> _getServerPort() {
    var completer = new Completer();
    var lockFile = new File(BUILDLOCK_FILE);
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
    _runScript("packages/buildtool/src/server.dart").then((process) {
      var sis = new StringInputStream(process.stdout);
      sis.onData = () {
        var line = sis.readLine();
        _logger.fine(line);
        if (line.startsWith("port: ")) {
          var port = int.parse(line.substring("port: ".length));
          completer.complete(port);
        } else if (line.startsWith("error")) {
          completer.completeError("error");
        }
      };
    });
    return completer.future;
  }
}