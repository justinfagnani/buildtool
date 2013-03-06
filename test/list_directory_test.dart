library list_directory_test;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/src/util/io.dart';
import 'package:buildtool/src/util/recursive_directory_lister.dart';
import 'package:buildtool/src/symlink.dart';
import 'package:unittest/unittest.dart';

main() {
  group('listDirectory', () {
    var testPath;
    var testDir;

    setUp(() {
      testDir = new Directory('test/data/symlinks').createTempSync();
      testPath = new Path(testDir.path);
    });

    tearDown(() {
      if (testDir.existsSync()) testDir.deleteSync(recursive: true);
    });

    /*
     * Tests listing 7 cases of files, directories and links:
     *   1. A file
     *   2. A directory
     *   3. A file in a directory
     *   4. A link to a file
     *   5. A link to a directory
     *   6  A file in a directory, reached by a link to that directory
     *   7. A broken link
     */
    test('listDirectory symlink mega test', () {
      new File.fromPath(testPath.append('file_target')).createSync();
      new Directory.fromPath(testPath.append('dir_target')).createSync();
      new File.fromPath(testPath.append('dir_target/file')).createSync();
      Future.wait([
        new Symlink('file_target', testPath.append('file_link').toString())
            .create(),
        new Symlink('dir_target', testPath.append('dir_link').toString())
            .create(),
        new Symlink('broken_target', testPath.append('broken_link').toString())
            .create()])
      .then(expectAsync1((_) {
        var results = [];

        listDirectory(testDir, (_) => true).listen((FileSystemEntity e) {
          if (e is File) {
            results.add("file: ${e.path} : ${e.fullPathSync()}");
          } else if (e is Directory) {
            var f = new File(e.path);
            results.add("dir: ${e.path} : ${f.fullPathSync()}");
          } else if (e is Symlink) {
            results.add("link: ${e.link} : ${e.target}");
          } else {
            throw "bad";
          }
        },
        onError: (AsyncError e) {
          expect(true, false);
        },
        onDone: expectAsync0(() {
          var testPathFull = new File.fromPath(testPath).fullPathSync();
          expect(results, unorderedEquals([
              "file: $testPath/file_target : $testPathFull/file_target",
              "dir: $testPath/dir_target : $testPathFull/dir_target",
              "file: $testPath/dir_target/file : $testPathFull/dir_target/file",
              "link: $testPath/file_link : $testPathFull/file_target",
              "link: $testPath/dir_link : $testPathFull/dir_target",
              "file: $testPath/dir_link/file : $testPathFull/dir_target/file",
              "link: $testPath/broken_link : null",
            ]));
        }));
      }));
    });

    test('conditional recursion', () {
      new Directory.fromPath(testPath.append('dir')).createSync();
      new File.fromPath(testPath.append('dir/file')).createSync();
      new Directory.fromPath(testPath.append('dir2')).createSync();
      new File.fromPath(testPath.append('dir2/file')).createSync();

      listDirectory(testDir, (e) => !e.path.endsWith('dir2')).toList()
      .then(expectAsync1((results) {
        expect(results.map((e) => e.path), unorderedEquals([
            "$testPath/dir",
            "$testPath/dir/file",
            "$testPath/dir2",
        ]));
      }));
    });

    test('symlink cycle', () {
      var dir = new Directory.fromPath(testPath.append('dir'))..createSync();
      new Symlink('../dir', testPath.append('dir/link').toString()).create()
        .then(expectAsync1((_) {
          var listing = listDirectory(dir, (_) => true);
          listing.toList().then(expectAsync1((list) {
            expect(list.length, 1);
            expect(list.first.target, getFullPath(dir.path));
          }));
        }));
    });
  });
}

String getFullPath(String path) => new File(path).fullPathSync();