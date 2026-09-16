import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:woochat_mobile/src/data/edge_function_auth.dart';

String jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, String>{'alg': 'HS256'})}.${part(payload)}.sig';
}

void main() {
  group('jwtHasSubject', () {
    test('a signed-in user token carries a subject', () {
      expect(
        jwtHasSubject(jwt(<String, dynamic>{
          'sub': 'a1b2c3',
          'role': 'authenticated',
        })),
        isTrue,
      );
    });

    test('the anon key does not — which is what the function rejects', () {
      // The real anon key's payload, minus the signature.
      expect(
        jwtHasSubject(jwt(<String, dynamic>{
          'role': 'anon',
          'iss': 'supabase',
          'iat': 1785765602,
          'exp': 2101125602,
        })),
        isFalse,
      );
    });

    test('an empty subject does not count', () {
      expect(jwtHasSubject(jwt(<String, dynamic>{'sub': ''})), isFalse);
    });

    test('anything that is not a JWT is refused rather than thrown on', () {
      expect(jwtHasSubject(''), isFalse);
      expect(jwtHasSubject('not-a-token'), isFalse);
      expect(jwtHasSubject('a.b'), isFalse);
      expect(jwtHasSubject('a.!!!not-base64!!!.c'), isFalse);
    });
  });
}
