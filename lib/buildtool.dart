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
 * To add a task, call [addRule] with a list of regexs for matching file names
 * and a task to run when files matching the regex change.
 *
 * Example:
 *
 *     main() {
 *       configure(() {
 *         addRule('web_ui', new WebComponentsTask(), [".*\.html"]);
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

import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/client.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/launcher.dart';
import 'package:buildtool/src/server.dart';
import 'package:buildtool/glob.dart';
import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

bool _isServer;
var _args;
bool _inConfigure = false;

Builder _builder;

/**
 * Adds a new [Task] to this build which is run when files match against the
 * [Glob] patterns in [files].
 *
 * [addRule] can only be called from within the closure passed to [configure].
 */
Task addRule(String name, Task task, List<String> files) {
  if (!_inConfigure) {
    throw new StateError("addTask must be called inside a configure() call.");
  }
  _builder.addRule(name, task, files);
  return task;
}

final Logger _logger = new Logger('buildtool');

/**
 * Configures the build. In [configClosure], [addRule] can be called to add
 * tasks to the build.
 *
 * [forceServer] is for debug and development purposes.
 */
/*
 * For code readers: configure() is called by a project's build.dart file.
 * build.dart is run one of two ways:
 *   1) As the interface to buildtool, usually launched by the Editor, but
 *      possibly from the command-line. In this mode all it does is communicate
 *      to the buildtool server, and launch it if necessary. The configuration
 *      is not used.
 *   2) As the buildtool server, if the --server flag is present. In this mode
 *      it launches an HTTP server and listens for build commands. The
 *      configuration is used here to create a Builder.
 */
void configure(void configClosure(), {bool forceServer: false,
  bool forceDeploy: false}) {
  _processArgs(forceServer: forceServer, forceDeploy: forceDeploy);
  // baseDir is where build.dart, source files and .buildlock are located.
  var baseDir = new Path(new Options().script).directoryPath;
  if (baseDir.toString() == '') {
    baseDir = new Path(Directory.current.path);
  }
  if (_isServer == true) {
    var server = new Server((Builder builder) {
      _builder = builder;
      _inConfigure = true;
      configClosure();
      _inConfigure = false;
    }, baseDir);
    server.start();
  } else {
    new Launcher(
        baseDir: baseDir,
        machine: _args['machine'],
        clean: _args['clean'],
        deploy: _args['deploy'],
        quit: _args['quit'],
        changed: _args['changed'],
        removed: _args['removed']).run();
  }
}

/** Handle --changed, --removed, --clean and --help command-line args. */
void _processArgs({bool forceServer, bool forceDeploy}) {
  var parser = new ArgParser()
    ..addFlag("server", help: "run buildtool as a long-running server")
    ..addOption("changed", help: "the file has changed since the last build",
        allowMultiple: true)
    ..addOption("removed", help: "the file was removed since the last build",
        allowMultiple: true)
    ..addFlag("clean", negatable: false, help: "remove any build artifacts")
    ..addFlag("deploy", defaultsTo: forceDeploy, help: "build a deploy directory")
    ..addFlag("full", negatable: false,
        help: "unimplemented: perform a full build.")
    ..addFlag("machine", negatable: false,
        help: "print machine parseable messages,"
              "used by tools like the Dart editor")
    ..addFlag("quit", negatable: false, help: "quit the build server")
    ..addFlag("help", negatable: false, help: "displays this help and exit");
  _args = parser.parse(new Options().arguments);
  _isServer = forceServer || _args['server'];
  if (_args["help"]) {
    print(parser.getUsage());
    exit(0);
  }
}
