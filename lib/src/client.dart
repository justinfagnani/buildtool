// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client;

import 'dart:async';
import 'dart:io';
import 'dart:json';
import 'dart:uri';
import 'package:buildtool/src/common.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

Logger _logger = new Logger('client');

typedef http.Client HttpClientFactory();

_defaultHttpClientFactory() => new http.Client();

/**
 * Client to a BuildServer.
 */
class Client {
  int port;

  final HttpClientFactory httpClientFactory;
  final IOSink _outputSink;
  var _connectionErrorHandler;

  Client(
    this.port,
    { IOSink outputSink,
    this.httpClientFactory: _defaultHttpClientFactory})
      : _outputSink = (outputSink == null) ? stdout : outputSink {

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

  Future quit() {
    _logger.fine("Quit...");
    return _sendCloseCommand();
  }

  Future<bool> build({
      bool clean: false,
      bool deploy: false,
      bool machine: false,
      List<String> changedFiles: const [],
      List<String> removedFiles: const []}) {
    _logger.info("Build... $deploy");
    var filteredFiles = changedFiles.where(isValidInputFile).toList();
    if (machine && filteredFiles.isEmpty) {
      _logger.info("no changed files");
      return new Future.immediate(true);
    } else {
      return _sendBuildCommand(filteredFiles, clean, deploy).then((Map result) {
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
          _outputSink.write("$message\n");
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
      bool cleanBuild,
      bool deploy) {
    return _sendJsonCommand(BUILD_URL, data: {
      'changed': changedFiles.toList(),
      'removed': [],
      'clean': cleanBuild,
      'deploy': deploy,
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
        client.close();
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

