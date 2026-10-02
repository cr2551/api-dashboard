import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

Map<String, Object?> service([Map<String, Object?> overrides = const {}]) => {
  'name': 'stripe',
  'type': 'stripe',
  ...overrides,
};

List<ServiceConfig> parse(List<Object?> services) =>
    parseServicesConfig({'services': services});

/// Expects parsing to fail with [field] named in the error.
void expectBadField(Object? json, String field, [Pattern? message]) {
  expect(
    () => parseServicesConfig(json),
    throwsA(
      isA<ConfigException>()
          .having((e) => e.field, 'field', field)
          .having((e) => e.toString(), 'message', contains(field))
          .having(
            (e) => e.message,
            'detail',
            message == null ? isNotEmpty : contains(message),
          ),
    ),
  );
}

void main() {
  group('valid config', () {
    test('minimal service gets the defaults', () {
      final s = parse([service()]).single;
      expect(s.name, 'stripe');
      expect(s.type, 'stripe');
      expect(s.endpoint, isNull);
      expect(s.interval, const Duration(seconds: 60));
      expect(s.timeout, const Duration(seconds: 10));
      const d = SlaPolicy(provider: 'stripe');
      expect(s.policy.provider, 'stripe');
      expect(s.policy.maxP95Latency, d.maxP95Latency);
      expect(s.policy.minUptimePercent, d.minUptimePercent);
      expect(s.policy.window, d.window);
      expect(s.policy.minSamples, d.minSamples);
      expect(s.policy.consecutiveFailures, 1);
    });

    test('every field is read', () {
      final s = parse([
        service({
          'endpoint': 'https://example.com/health',
          'intervalSeconds': 15,
          'timeoutSeconds': 5,
          'sla': {
            'maxP95LatencyMs': 400,
            'minUptimePercent': 99,
            'windowMinutes': 30,
            'minSamples': 3,
            'minLatencySamples': 20,
            'consecutiveFailures': 2,
          },
        }),
      ]).single;
      expect(s.policy.minLatencySamples, 20);
      expect(s.endpoint, Uri.parse('https://example.com/health'));
      expect(s.interval, const Duration(seconds: 15));
      expect(s.timeout, const Duration(seconds: 5));
      expect(s.policy.maxP95Latency, const Duration(milliseconds: 400));
      expect(s.policy.minUptimePercent, 99.0);
      expect(s.policy.window, const Duration(minutes: 30));
      expect(s.policy.minSamples, 3);
      expect(s.policy.consecutiveFailures, 2);
    });

    test('minLatencySamples is off unless set', () {
      final s = parse([
        service({
          'sla': {'minSamples': 5},
        }),
      ]).single;
      expect(s.policy.minLatencySamples, isNull);
    });

    test('minLatencySamples must be a whole number of 1 or more', () {
      expectBadField(
        {
          'services': [
            service({
              'sla': {'minLatencySamples': 0},
            }),
          ],
        },
        'services[0].sla.minLatencySamples',
        '1 or more',
      );
    });

    test('several services keep their own settings', () {
      final list = parse([
        service({'name': 'a', 'intervalSeconds': 10}),
        service({'name': 'b', 'intervalSeconds': 20}),
      ]);
      expect(list.map((s) => s.name), ['a', 'b']);
      expect(list.map((s) => s.interval.inSeconds), [10, 20]);
      expect(list.map((s) => s.policy.provider), ['a', 'b']);
    });

    test('integer uptime percent is accepted', () {
      final s = parse([
        service({
          'sla': {'minUptimePercent': 100},
        }),
      ]).single;
      expect(s.policy.minUptimePercent, 100.0);
    });
  });

  group('errors name the bad field', () {
    test('root must be an object', () {
      expectBadField([], 'config', 'object');
    });

    test('unknown top-level field', () {
      expectBadField({'services': [], 'servces': 1}, 'servces', 'unknown');
    });

    test('services missing, wrong type or empty', () {
      expectBadField(<String, Object?>{}, 'services', 'required');
      expectBadField({'services': 'x'}, 'services', 'list');
      expectBadField({'services': []}, 'services', 'at least one');
    });

    test('service must be an object', () {
      expectBadField({
        'services': ['stripe'],
      }, 'services[0]');
    });

    test('name and type are required', () {
      expectBadField({
        'services': [
          {'type': 'stripe'},
        ],
      }, 'services[0].name');
      expectBadField({
        'services': [
          {'name': 'x'},
        ],
      }, 'services[0].type');
      expectBadField({
        'services': [
          service({'name': '  '}),
        ],
      }, 'services[0].name');
    });

    test('unknown type lists the supported ones', () {
      expectBadField(
        {
          'services': [
            service({'type': 'paypal'}),
          ],
        },
        'services[0].type',
        'supported: stripe',
      );
    });

    test('duplicate names point at the second one', () {
      expectBadField(
        {
          'services': [service(), service()],
        },
        'services[1].name',
        'duplicate',
      );
    });

    test('unknown service field (typo) is rejected', () {
      expectBadField(
        {
          'services': [
            service({'intervalSecs': 10}),
          ],
        },
        'services[0].intervalSecs',
        'intervalSeconds',
      );
    });

    test('endpoint must be an http(s) URL', () {
      for (final bad in ['nope', 'ftp://x.com', 'https://', 42]) {
        expectBadField({
          'services': [
            service({'endpoint': bad}),
          ],
        }, 'services[0].endpoint');
      }
    });

    test('numbers must be whole and positive', () {
      for (final bad in [0, -5, 1.5, '30', null]) {
        expectBadField(
          {
            'services': [
              service({'intervalSeconds': bad}),
            ],
          },
          'services[0].intervalSeconds',
          'whole number',
        );
      }
      expectBadField({
        'services': [
          service({'timeoutSeconds': 0}),
        ],
      }, 'services[0].timeoutSeconds');
    });

    test('sla fields are validated with their full path', () {
      expectBadField(
        {
          'services': [
            service({
              'sla': {'minUptimePercent': 101},
            }),
          ],
        },
        'services[0].sla.minUptimePercent',
        'between 0 and 100',
      );
      expectBadField({
        'services': [
          service({
            'sla': {'minUptimePercent': 'high'},
          }),
        ],
      }, 'services[0].sla.minUptimePercent');
      expectBadField({
        'services': [
          service({
            'sla': {'maxP95LatencyMs': -1},
          }),
        ],
      }, 'services[0].sla.maxP95LatencyMs');
      expectBadField({
        'services': [
          service({
            'sla': {'consecutiveFailures': 0},
          }),
        ],
      }, 'services[0].sla.consecutiveFailures');
      expectBadField(
        {
          'services': [
            service(),
            service({'name': 'b', 'sla': 5}),
          ],
        },
        'services[1].sla',
        'object',
      );
      expectBadField({
        'services': [
          service({
            'sla': {'windowMin': 5},
          }),
        ],
      }, 'services[0].sla.windowMin');
    });
  });

  group('displayName', () {
    test('is optional and defaults to null', () {
      expect(parse([service()]).single.displayName, isNull);
    });

    test('is read and trimmed', () {
      final s = parse([
        service({'displayName': '  GitHub '}),
      ]).single;
      expect(s.displayName, 'GitHub');
      expect(s.name, 'stripe', reason: 'the key is unchanged');
    });

    test('must be a non-empty string of at most 40 characters', () {
      for (final bad in ['', '   ', 5, null]) {
        expectBadField({
          'services': [
            service({'displayName': bad}),
          ],
        }, 'services[0].displayName');
      }
      expectBadField(
        {
          'services': [
            service({'displayName': 'x' * 41}),
          ],
        },
        'services[0].displayName',
        '40 characters',
      );
    });
  });

  group('type http', () {
    Map<String, Object?> http([Map<String, Object?> extra = const {}]) =>
        service({
          'name': 'gh',
          'type': 'http',
          'endpoint': 'https://api.github.com/rate_limit',
          ...extra,
        });

    test('reads the endpoint and expectedStatus', () {
      final s = parse([
        http({'expectedStatus': 204}),
      ]).single;
      expect(s.type, 'http');
      expect(s.endpoint, Uri.parse('https://api.github.com/rate_limit'));
      expect(s.expectedStatus, 204);
    });

    test('expectedStatus defaults to any 2xx (null)', () {
      expect(parse([http()]).single.expectedStatus, isNull);
    });

    test('the endpoint is required', () {
      expectBadField(
        {
          'services': [
            {'name': 'gh', 'type': 'http'},
          ],
        },
        'services[0].endpoint',
        'required',
      );
    });

    test('expectedStatus must be a status code', () {
      for (final bad in [99, 600, '200', 200.5]) {
        expectBadField(
          {
            'services': [
              http({'expectedStatus': bad}),
            ],
          },
          'services[0].expectedStatus',
          'between 100 and 599',
        );
      }
    });

    test('expectedStatus is only for type http', () {
      expectBadField(
        {
          'services': [
            service({'expectedStatus': 200}),
          ],
        },
        'services[0].expectedStatus',
        'only supported',
      );
    });
  });

  group('loadServicesConfig', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('services_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a file', () {
      final path = '${dir.path}/services.json';
      File(path)
          .writeAsStringSync('{"services":[{"name":"s","type":"stripe"}]}');
      expect(loadServicesConfig(path).single.name, 's');
    });

    test('missing file and invalid JSON name the path', () {
      final missing = '${dir.path}/nope.json';
      expect(
        () => loadServicesConfig(missing),
        throwsA(
          isA<ConfigException>().having((e) => e.field, 'field', missing),
        ),
      );
      final bad = '${dir.path}/bad.json';
      File(bad).writeAsStringSync('{not json');
      expect(
        () => loadServicesConfig(bad),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.field, 'field', bad)
              .having((e) => e.message, 'message', contains('JSON')),
        ),
      );
    });

    test('the committed services.chaos.example.json is valid', () {
      final list = loadServicesConfig('../services.chaos.example.json');
      expect(list.map((s) => s.name), [
        'down-5xx',
        'client-4xx',
        'slow',
        'times-out',
        'flaky',
        'wrong-status',
        'no-such-host',
        'bad-cert',
      ]);
      expect(list.every((s) => s.displayName != null), isTrue);
      expect(list.every((s) => s.type == 'http'), isTrue);
      // The timeout scenario only makes sense when the timeout is shorter
      // than the endpoint's delay.
      final timesOut = list.firstWhere((s) => s.name == 'times-out');
      expect(timesOut.timeout, const Duration(seconds: 2));
      expect(timesOut.endpoint.toString(), endsWith('/delay/5'));
      expect(
        list.firstWhere((s) => s.name == 'wrong-status').expectedStatus,
        200,
      );
    });

    test('the committed services.example.json is valid', () {
      final list = loadServicesConfig('../services.example.json');
      expect(list.map((s) => s.name), [
        'stripe',
        'github',
        'frankfurter',
        'httpbin',
      ]);
      expect(list.map((s) => s.type), ['stripe', 'http', 'http', 'http']);
      expect(list.first.policy.consecutiveFailures, 2);
      expect(list.map((s) => s.policy.minLatencySamples).toSet(), {20});
      // Each service has its own thresholds.
      expect(list.map((s) => s.policy.minUptimePercent).toSet().length, 3);
      expect(list.every((s) => s.type != 'http' || s.endpoint != null), isTrue);
    });
  });
}
