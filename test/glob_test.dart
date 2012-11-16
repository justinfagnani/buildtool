// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library glob_test;

import 'package:unittest/unittest.dart';
import 'package:buildtool/glob.dart';

main() {
  test('glob', () {
    expectGlob("*.html", 
        matches: ["a.html", "_-\a.html", r"^$*?.html", "()[]{}.html", "↭.html", 
                  "\u21ad.html", "♥.html", "\u2665.html"],
        nonMatches: ["a.htm", "a.htmlx", "/a.html"]);
    
    expectGlob("**/*.html", 
        matches: ["/a.html", "a/b.html", "a/b/c.html", "a/b/c.html/d.html"],
        nonMatches: ["a.html", "a/b.html/c"]);

    expectGlob("foo.*", 
        matches: ["foo.html"],
        nonMatches: ["afoo.html", "foo/a.html", "foo.html/a"]);

    expectGlob("a?", 
        matches: ["ab", "a?", "a↭", "a\u21ad", "a\\"],
        nonMatches: ["a", "abc"]);
  });
}

expectGlob(String pattern, { List<String> matches, List<String> nonMatches}) {
  var glob = new Glob(pattern);
  for (var str in matches) {
    expect(glob.hasMatch(str), true);
    var m = new List.from(glob.allMatches(str));
    expect(m.length, 1);
    expect(m[0].str, str);
  }
  for (var str in nonMatches) {
    expect(glob.hasMatch(str), false);
    var m = new List.from(glob.allMatches(str));
    expect(m.length, 0);
  }
}
