// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library glob;

/**
 * A [Pattern] that matches against path strings with wildcards.
 * 
 * The pattern matches strings as follows:
 *   * The whole string must match, not a substring
 *   * Any non wildcard is matched as a literal
 *   * '*' matches one or more characters except '/'
 *   * '?' matches exactly one character except '/'
 *   * '**' matches one or more characters including '/'
 */
class Glob implements Pattern {
  final regex;
  
  Glob(String pattern) : regex = _regexpFromGlobPattern(pattern);
  
  Iterable<Match> allMatches(String str) => regex.allMatches(str);
  
  bool hasMatch(String str) => regex.hasMatch(str);
}

// From the PatternCharacter rule here:
// http://ecma-international.org/ecma-262/5.1/#sec-15.10
final _specialChars = new RegExp(r'[\\\^\$\.\|\+\[\]\(\)\{\}]');

RegExp _regexpFromGlobPattern(String pattern) {
  var sb = new StringBuffer();
  sb.add('^');
  var chars = pattern.splitChars();
  for (var i = 0; i < chars.length; i++) {
    var c = chars[i];
    if (_specialChars.hasMatch(c)) {
      sb.add('\\$c');
    } else if (c == '*') {
      if ((i + 1 < chars.length) && (chars[i + 1] == '*')) {
        sb.add('.*');
        i++;
      } else {
        sb.add('[^/]*');
      }
    } else if (c == '?') {
      sb.add('[^/]');
    } else {
      sb.add(c);
    }
  }
  sb.add(r'$');
  return new RegExp(sb.toString());
}
