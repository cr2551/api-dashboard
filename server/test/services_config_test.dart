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
            'consecutiveFailures': 2,
          },
        }),
      ]).single;
      expect(s.endpoint, Uri.parse('https://example.com/health'));
      expect(s.interval, const Duration(seconds: 15));
      expect(s.timeout, const Duration(seconds: 5));
      expect(s.policy.maxP95Latency, const Duration(milliseconds: 400));
      expect(s.policy.minUptimePercent, 99.0);
      expect(s.policy.window, const Duration(minutes: 30));
      expect(s.policy.minSamples, 3);
      expect(s.policy.consecutiveFailures, 2);
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

    test('the committed services.example.json is valid', () {
      final s = loadServicesConfig('../services.example.json').single;
      expect(s.name, 'stripe');
      expect(s.policy.consecutiveFailures, 2);
    });
  });
}
