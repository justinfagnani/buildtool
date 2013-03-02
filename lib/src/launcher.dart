// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.launcher;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/src/client.dart';
import 'package:buildtool/src/common.dart';
import 'package:logging/logging.dart';

typedef Future<Process> ScriptRunner(String executable, List<String> args);

// This function should not do anything other than call Process.start, because
// it's not tested.
_defaultRunScript(String executable, List<String> args) {
  return Process.start(executable, args);
}

typedef Client ClientFactory(int port);

_defaultClientFactory(int port) => new Client(port);

final int _CONNECTION_REFUSED = 61;

Logger _logger = new Logger('launcher');

/**
 * Starts a buildtool client/server pair. A Launcher first tries to connect to a
 * running buildtool server by looking for a .buildlock file. If there is no
 * running server, then it starts one. Then the Launcher creates a client with
 * options specified from the commandline arguments.
 */
class Launcher {
  final ScriptRunner _runScript;
  final ClientFactory _clientFactory;
  final Options _options;

  final Path baseDir;
  final bool machine;
  final bool clean;
  final bool deploy;
  final bool quit;
  final List<String> changed;
  final List<String> removed;

  Launcher({
    this.baseDir,
    this.machine,
    this.clean,
    this.deploy,
    this.changed,
    this.removed,
    this.quit,
    ClientFactory clientFactory: _defaultClientFactory,
    ScriptRunner runScript: _defaultRunScript,
    Options options})
      : _clientFactory = clientFactory,
        _runScript = runScript,
        _options = (options != null) ? options : new Options();

  Future<bool> run() {
    int retryCount = 0;
    return _getServerPort().then((port) {
      var client = _clientFactory(port);
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
      if (quit == true) {
        return client.quit();
      } else {
        return client.build(
            machine: machine,
            clean: clean,
            deploy: deploy,
            changedFiles: changed,
            removedFiles: removed);
      }
    });
  }

  /**
   * Returns the port of the running builtool server, or starts a new server.
   */
  Future<int> _getServerPort() {
    var completer = new Completer();
    var lockFile = new File.fromPath(baseDir.append(BUILDLOCK_FILE));
    if (lockFile.existsSync()) {
      try {
        var contents = lockFile.readAsStringSync();
        var port = int.parse(contents);
        _logger.fine("Server already running onport: $port");

        // Check that the lockfile was created after build.dart, if not
        // restart the server.
        var buildScriptPath = _options.script;
        var buildScript = new File(buildScriptPath);
        var buildLastModified = buildScript.lastModifiedSync();

        var lockLastModified = lockFile.lastModifiedSync();
        if (buildLastModified.isBefore(lockLastModified)) {
          completer.complete(port);
        } else {
          // restart server
          var client = new Client(port);
          client.quit().then((_) {
            _startServer().then((v) => completer.complete(v));
          });
        }
      } on Error catch (e) {
        completer.completeError(e);
      }
    } else {
      _startServer().then((v) => completer.complete(v));
    }
    return completer.future;
  }

  // set to false in development to be able to see output from the server when
  // running the build script manually
  final bool detachServer = true;

  Future<int> _startServer() {
    _logger.info("Starting build server");
    var completer = new Completer();
    _logger.info("build script: ${_options.script}");
    var vmExecutable = _options.executable;
    _runScript(vmExecutable, [_options.script, '--server']).then((process) {
      _logger.info("Server started");
      process.stdout
        .transform(new StringDecoder())
        .transform(new LineTransformer())
        .listen((String line) {
          _logger.fine("server: $line");
          if (line.startsWith("port: ")) {
            var port = int.parse(line.substring("port: ".length));
            completer.complete(port);
          } else if (line.startsWith("error")) {
            completer.completeError("error");
          }
        },
        onDone: () {
          _logger.info("Server stopped: ${process.exitCode}");
        });
      });
    return completer.future;
  }
}
