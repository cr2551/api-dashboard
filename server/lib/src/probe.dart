import 'probe_result.dart';

/// Something that can run one probe against an external provider.
abstract interface class Probe {
  String get provider;

  /// Runs one probe. Must not throw: failures are reported in the result.
  Future<ProbeResult> run();
}
