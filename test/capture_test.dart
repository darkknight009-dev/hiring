import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/models/captured_post.dart';
import 'package:hiring/services/capture/android_capture_provider.dart';
import 'package:hiring/services/capture/web_capture_provider.dart';

void main() {
  const postUrl = 'https://www.linkedin.com/posts/fictional-team_hiring-123';

  group('CapturedPost input contract', () {
    test('accepts text only, URL only, and both; normalizes whitespace', () {
      final text = CapturedPost.fromInput(text: '  We are hiring!\n ');
      expect(text.text, 'We are hiring!');
      expect(text.url, isNull);
      final url = CapturedPost.fromInput(url: ' $postUrl ');
      expect(url.text, isNull);
      expect(url.url, Uri.parse(postUrl));
      final both = CapturedPost.fromInput(text: 'Hello', url: postUrl);
      expect(both.text, 'Hello');
      expect(both.url, Uri.parse(postUrl));
    });

    test('rejects empty and oversized content', () {
      expect(
        () => CapturedPost.fromInput(text: ' \n ', url: ' '),
        throwsFormatException,
      );
      expect(
        () => CapturedPost.fromInput(text: 'a' * 20001),
        throwsFormatException,
      );
      expect(CapturedPost.fromInput(text: 'a' * 20000).text!.length, 20000);
      expect(
        () => CapturedPost.fromInput(url: '$postUrl${'a' * 2048}'),
        throwsFormatException,
      );
    });

    test(
      'rejects misleading hosts, unsupported schemes, and non-post links',
      () {
        for (final url in [
          'not a url',
          'http://www.linkedin.com/posts/test',
          'javascript:alert(1)',
          'https://linkedin.com.evil.example/posts/test',
          'https://evil-linkedin.com/posts/test',
          'https://linkedin.com@evil.example/posts/test',
          'https://user:password@linkedin.com/posts/test',
          'https://linkedin.com:8080/posts/test',
          'https://www.linkedin.com/',
          'https://www.linkedin.com/in/example',
          'https://www.linkedin.com/posts/',
          'https://www.linkedin.com/posts/has whitespace',
        ]) {
          expect(
            () => CapturedPost.fromInput(url: url),
            throwsFormatException,
            reason: url,
          );
        }
      },
    );

    test('accepts public LinkedIn post link formats without fetching them', () {
      for (final url in [
        postUrl,
        'https://linkedin.com/feed/update/urn:li:activity:123',
        'https://in.linkedin.com/posts/example?utm_source=share',
        'https://www.linkedin.com/pulse/example-article',
        'https://lnkd.in/abc123',
        'https://www.lnkd.in/dQw4w9Gc',
      ]) {
        expect(CapturedPost.fromInput(url: url).url.toString(), url);
      }
    });

    test('still rejects look-alike lnkd.in hosts', () {
      for (final url in [
        'https://lnkd.in.evil.example/abc123',
        'https://evil-lnkd.in/abc123',
        'http://lnkd.in/abc123',
      ]) {
        expect(
          () => CapturedPost.fromInput(url: url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });

  test(
    'manual provider returns supplied input, supports cancellation',
    () async {
      final input = CapturedPost.fromInput(text: 'User-supplied text');
      final provider = WebCaptureProvider(readDraft: () => input);
      expect(await provider.capturePost(), same(input));
      expect(
        await const WebCaptureProvider(readDraft: _cancel).capturePost(),
        isNull,
      );
    },
  );

  test('Android placeholder explicitly rejects unsupported capture', () {
    expect(
      () => AndroidCaptureProvider().capturePost(),
      throwsUnsupportedError,
    );
  });
}

CapturedPost? _cancel() => null;
