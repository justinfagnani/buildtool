// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client_test;

import 'dart:io';
import 'dart:json';
import 'dart:utf';
import 'package:args/args.dart';
import 'package:buildtool/src/client.dart';
import 'package:buildtool/src/common.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http;
import 'package:unittest/mock.dart';
import 'package:unittest/unittest.dart';
import 'mock_task.dart';

main() {
  test('BuildClient.build', () {
    var requestBody;
    var httpClientMock = new http.MockClient((request) {
      if (request.url.path == '/build') {
        requestBody = parse(request.body);
        expect(requestBody, containsPair('changed', ['a']));
        // removed is not implemented. when it is this will fail
        expect(requestBody, containsPair('removed', []));
        expect(requestBody, containsPair('clean', true));
        var json = stringify({
            'status': 'OK',
            'messages': ['message1'],
            'mappings': [{'from': 'a', 'to': 'b'}],
          });
        return new http.Response(json, 200);
      }
    });
    var port = 12345;
    var clientOut = new ListOutputStream();

    var client = new Client(port,
        outputStream: clientOut,
        httpClientFactory: () => httpClientMock);

    client.build(
        clean: true,
        changedFiles: ['a'],
        removedFiles: ['b']).then(expectAsync1((_) {
      List response = parse(decodeUtf8(clientOut.read()));
      expect(response.length, 1);
      expect(response, contains(equals(
          {'method': 'mapping', 'params': {'from': 'a', 'to': 'b'}})));
    }));
  });
}
