/// Data models for Teensy deployment workflow.
///
/// Mirrors the Python backend schemas from:
/// - neurocnl TeensyNetworkResponse
/// - Neurochip FlashJob / FlashStatus
/// - neurodreamhand VerificationReport

enum TeensyDeploymentVerdict {
  faithful,
  approximate,
  notDeployable;

  static TeensyDeploymentVerdict fromString(String value) {
    switch (value) {
      case 'faithful':
        return TeensyDeploymentVerdict.faithful;
      case 'approximate':
        return TeensyDeploymentVerdict.approximate;
      case 'not_deployable':
        return TeensyDeploymentVerdict.notDeployable;
      default:
        return TeensyDeploymentVerdict.notDeployable;
    }
  }
}

/// Response from POST /api/deploy/teensy/network.
class TeensyNetworkResponse {
  final TeensyDeploymentVerdict verdict;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? payload;

  const TeensyNetworkResponse({
    required this.verdict,
    required this.warnings,
    required this.rejectionReasons,
    this.payload,
  });

  factory TeensyNetworkResponse.fromJson(Map<String, dynamic> json) {
    return TeensyNetworkResponse(
      verdict: TeensyDeploymentVerdict.fromString(json['verdict'] as String),
      warnings:
          (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons:
          (json['rejection_reasons'] as List).map((e) => e as String).toList(),
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}

enum FlashJobStatus {
  pending,
  compiling,
  uploading,
  verifying,
  done,
  failed;

  static FlashJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return FlashJobStatus.pending;
      case 'compiling':
        return FlashJobStatus.compiling;
      case 'uploading':
        return FlashJobStatus.uploading;
      case 'verifying':
        return FlashJobStatus.verifying;
      case 'done':
        return FlashJobStatus.done;
      case 'failed':
        return FlashJobStatus.failed;
      default:
        return FlashJobStatus.pending;
    }
  }

  double get progressFraction {
    switch (this) {
      case FlashJobStatus.pending:
        return 0.0;
      case FlashJobStatus.compiling:
        return 0.25;
      case FlashJobStatus.uploading:
        return 0.5;
      case FlashJobStatus.verifying:
        return 0.75;
      case FlashJobStatus.done:
        return 1.0;
      case FlashJobStatus.failed:
        return 0.0;
    }
  }
}

/// Flash job status from GET /api/neurochip/serial/flash/{job_id}.
class FlashJob {
  final String jobId;
  final FlashJobStatus status;
  final double progressPct;
  final String? message;
  final String? error;
  final Map<String, dynamic>? verificationReport;

  const FlashJob({
    required this.jobId,
    required this.status,
    this.progressPct = 0.0,
    this.message,
    this.error,
    this.verificationReport,
  });

  factory FlashJob.fromJson(Map<String, dynamic> json) {
    return FlashJob(
      jobId: json['job_id'] as String,
      status: FlashJobStatus.fromString(json['status'] as String),
      progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] as String?,
      error: json['error'] as String?,
      verificationReport:
          json['verification_report'] as Map<String, dynamic>?,
    );
  }
}

/// Serial port info from GET /api/neurochip/serial/ports.
class SerialPortInfo {
  final String device;
  final String? description;
  final String? hwid;
  final bool isTeensy;

  const SerialPortInfo({
    required this.device,
    this.description,
    this.hwid,
    this.isTeensy = false,
  });

  factory SerialPortInfo.fromJson(Map<String, dynamic> json) {
    final desc = json['description'] as String? ?? '';
    final hwid = json['hwid'] as String? ?? '';
    final isTeensy = desc.toLowerCase().contains('teensy') ||
        hwid.toLowerCase().contains('16c0:0483');
    return SerialPortInfo(
      device: json['device'] as String,
      description: json['description'] as String?,
      hwid: json['hwid'] as String?,
      isTeensy: isTeensy,
    );
  }
}

/// Protocol smoke check result from VerificationReport.
class ProtocolSmokeResult {
  final bool connected;
  final double? latencyMs;
  final String? error;

  const ProtocolSmokeResult({
    required this.connected,
    this.latencyMs,
    this.error,
  });

  factory ProtocolSmokeResult.fromJson(Map<String, dynamic> json) {
    return ProtocolSmokeResult(
      connected: json['connected'] as bool,
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      error: json['error'] as String?,
    );
  }
}

/// Hardware demo result from VerificationReport.
class HardwareDemoResult {
  final bool triggered;
  final int framesReceived;

  const HardwareDemoResult({
    required this.triggered,
    required this.framesReceived,
  });

  factory HardwareDemoResult.fromJson(Map<String, dynamic> json) {
    return HardwareDemoResult(
      triggered: json['triggered'] as bool,
      framesReceived: json['frames_received'] as int? ?? 0,
    );
  }
}

/// Full verification report from POST /api/neurochip/serial/flash/{job_id}/verify.
class VerificationReport {
  final String serialPort;
  final bool passed;
  final String summary;
  final ProtocolSmokeResult smoke;
  final HardwareDemoResult? demo;

  const VerificationReport({
    required this.serialPort,
    required this.passed,
    required this.summary,
    required this.smoke,
    this.demo,
  });

  factory VerificationReport.fromJson(Map<String, dynamic> json) {
    return VerificationReport(
      serialPort: json['serial_port'] as String,
      passed: json['passed'] as bool,
      summary: json['summary'] as String,
      smoke: ProtocolSmokeResult.fromJson(
          json['smoke'] as Map<String, dynamic>),
      demo: json['demo'] != null
          ? HardwareDemoResult.fromJson(
              json['demo'] as Map<String, dynamic>)
          : null,
    );
  }
}
