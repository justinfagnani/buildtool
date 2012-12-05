// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * buildtool is a simple build system for Dart that works well standalone or 
 * with the Dart Editor. buildtool configurations are simple Dart scripts.
 * 
 * ## Usage ##
 * 
 * Builds are configured by adding a set of tasks, and the files they should be
 * run against, in a closure provided to [configure].
 * 
 * To add a task, call [addTask] with a list of regexs for matching file names
 * and a task to run when files matching the regex change.
 * 
 * Example:
 * 
 *     main() {
 *       configure(() {
 *         addTask([".*\.html"], new WebComponentsTask());
 *       });
 *     }
 * 
 * For convenience, we recommend that developers providing tasks for their
 * tools to also provide a function that helps users register them, so for
 * example a user can simple install a task as follows:
 * 
 *     import 'package:buildtool/web_components.dart';
 *     
 *     main() {
 *       configure(() {
 *         webComponents(files: [".*\.html"]);
 *       });
 *     }
 * 
 * ## Client / Server Architecture ##
 * 
 * buildtool starts a seperate Dart process to run the build. This is done to
 * reduce startup times, allow the VM to warm up hot code in tasks, and to
 * preserve dependency information in memory.
 * 
 * The `server` flag controls whether buildtool is running as a server, or as a
 * client.
 * 
 * When executed as a client, without the `server` flag, the script looks for a
 * running buildtool server by reading the `.buildlock` file. If it can't find
 * running server, it starts one.
 * 
 * When running as a server, an HTTP server is started which listens for build
 * commands via a JSON-based protocol.
 * 
 * ## Warning ##
 * 
 * This library is extremely new and unfinished. It may change at any time.
 */
library buildtool;

import 'dart:io';
import 'dart:json';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:buildtool/glob.dart';
import 'package:buildtool/src/client.dart';
import 'package:buildtool/src/server.dart';
import 'package:buildtool/task.dart';

bool _isServer;
var _args;
bool _inConfigure = false;

/**
 * Adds a new [Task] to this build which is run when files match against the
 * regex patterns in [files].
 * 
 * [addTask] can only be called from within the closure passed to [configure].
 */
void addTask(List<String> files, Task task) {
  if (!_inConfigure) {
    throw new StateError("addTask must be called inside a configure() call.");
  }
  builder.addTask(files, task);
}

/**
 * Configures the build. In [configClosure], [addTask] can be called to add
 * tasks to the build.
 * 
 * [forceServer] is for debug and development purposes.
 */
void configure(void configClosure(), {bool forceServer: false}) {
  _processArgs(forceServer);
  if (_isServer == true) {
    _inConfigure = true;
    configClosure();
    _inConfigure = false;
    serverMain();
  } else {
    clientMain(_args);
  }
}

/** Handle --changed, --removed, --clean and --help command-line args. */
void _processArgs(bool forceServer) {
  var parser = new ArgParser()
    ..addFlag("server", help: "run build tool as a long-runing server")
    ..addOption("changed", help: "the file has changed since the last build",
        allowMultiple: true)
    ..addOption("removed", help: "the file was removed since the last build",
        allowMultiple: true)
    ..addFlag("clean", negatable: false, help: "remove any build artifacts")
    ..addFlag("quit", negatable: false, help: "quit the build server")
    ..addFlag("help", negatable: false, help: "displays this help and exit");
  _args = parser.parse(new Options().arguments);
  _isServer = forceServer || _args['server'];
  if (_args["help"]) {
    print(parser.getUsage());
    exit(0);
  }
}
