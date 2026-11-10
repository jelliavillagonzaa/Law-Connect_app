import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/widgets/common/case_signature_pad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a drawn stroke becomes a png and Clear removes it', () async {
    final pad = CaseSignatureController()..updateSize(const Size(200, 80));
    expect(pad.hasSignature, isFalse);
    expect(await pad.toPngBytes(), isNull);

    pad
      ..startStroke(const Offset(12, 20))
      ..extendStroke(const Offset(80, 40))
      ..endStroke();
    expect(pad.hasSignature, isTrue);

    final bytes = await pad.toPngBytes();
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(8));

    final record = await pad.toCaseRecord(
      signerId: 'uid-1',
      signerName: 'Jane Torres',
      signerRole: 'Attorney',
    );
    expect(record, isNotNull);
    expect(record!['signerName'], 'Jane Torres');
    expect(record['signerRole'], 'Attorney');
    expect(base64Decode(record['imageBase64'] as String), isNotEmpty);

    pad.clear();
    expect(pad.hasSignature, isFalse);
    expect(await pad.toPngBytes(), isNull);
  });
}
