library list_directory_test;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/src/util/io.dart';
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
      new Link.fromPath(testPath.append('file_link')).createSync('file_target');
      new Link.fromPath(testPath.append('dir_link')).createSync('dir_target');
      new Link.fromPath(testPath.append('broken_link'))
          .createSync('broken_target');

      var results = [];

      visitDirectory(testDir, (FileSystemEntity e) {
        if (e is File) {
          results.add("file: ${e.path}");
        } else if (e is Directory) {
          results.add("dir: ${e.path}");
        } else if (e is Link) {
          results.add("link: ${e.path}, ${e.targetSync()}");
        } else {
          throw "bad";
        }
        return new Future.value(true);
      }).then(expectAsync1((_) {
        var testPathFull = new File.fromPath(testPath).fullPathSync();
        var expectation = [
         "file: $testPath/file_target",
         "dir: $testPath/dir_target",
         "file: $testPath/dir_target/file",
         "link: $testPath/file_link, file_target",
         "link: $testPath/dir_link, dir_target",
         "file: $testPath/dir_link/file",
         "link: $testPath/broken_link, broken_target",
         ];
        expect(results, unorderedEquals(expectation));
      }));
    });

    test('conditional recursion', () {
      new Directory.fromPath(testPath.append('dir')).createSync();
      new File.fromPath(testPath.append('dir/file')).createSync();
      new Directory.fromPath(testPath.append('dir2')).createSync();
      new File.fromPath(testPath.append('dir2/file')).createSync();

      var files = [];
      visitDirectory(testDir, (e) {
        files.add(e);
        return new Future.value(!e.path.endsWith('dir2'));
      }).then(expectAsync1((_) {
        expect(files.map((e) => e.path), unorderedEquals([
            "$testPath/dir",
            "$testPath/dir/file",
            "$testPath/dir2",
        ]));
      }));
    });

    test("symlink cycles don't cause infinite recursion", () {
      var dir = new Directory.fromPath(testPath.append('dir'))..createSync();
      new Link.fromPath(testPath.append('dir/link')).createSync('../dir');
      var files = [];
      visitDirectory(dir, (e) {
        files.add(e);
        return new Future.value(true);
      }).then(expectAsync1((_) {
        expect(files.length, 1);
        expect(files.first.targetSync(), '../dir');
      }));
    });
  });
}

String getFullPath(String path) {
  try {
    return new File(path).fullPathSync();
  } on FileIOException catch(e) {
    return null;
  }
}