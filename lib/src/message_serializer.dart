import 'dart:convert';
import 'dart:typed_data';

// Use relative imports — importing the barrel file (phoenix_socket.dart) from
// inside lib/src/ creates a circular dependency because the barrel re-exports
// this file. Always use relative paths within lib/src/.
import 'utils/binary_decoder.dart';
import 'events.dart';
import 'message.dart';
import 'utils/map_utils.dart';

typedef DecoderCallback = dynamic Function(String rawData);
typedef EncoderCallback = String Function(Object? data);
typedef PayloadDecoderCallback = dynamic Function(Uint8List payload);

/// Serializes and deserializes [Message] instances to and from the wire format.
///
/// Each [PhoenixSocket] owns exactly one [MessageSerializer] instance,
/// resolved from [SerializerRegistry] at socket-creation time.
///
/// All three callbacks can be replaced at runtime via setters or [update].
class MessageSerializer {
  MessageSerializer({
    this.name = 'json',
    DecoderCallback decoder = jsonDecode,
    EncoderCallback encoder = jsonEncode,
    PayloadDecoderCallback? payloadDecoder,
  })  : _decoder = decoder,
        _encoder = encoder,
        _payloadDecoder = payloadDecoder;

  /// The codec name this serializer was created from.
  ///
  /// Set by [SerializerRegistry] for logging / introspection. Has no effect
  /// on encoding or decoding behaviour.
  final String name;

  DecoderCallback _decoder;
  EncoderCallback _encoder;
  PayloadDecoderCallback? _payloadDecoder;

  // ── Getters / setters ─────────────────────────────────────────────────────

  DecoderCallback get decoder => _decoder;
  set decoder(DecoderCallback v) => _decoder = v;

  EncoderCallback get encoder => _encoder;
  set encoder(EncoderCallback v) => _encoder = v;

  PayloadDecoderCallback? get payloadDecoder => _payloadDecoder;
  set payloadDecoder(PayloadDecoderCallback? v) => _payloadDecoder = v;

  // ── Atomic update ─────────────────────────────────────────────────────────

  /// Atomically replaces one or more codec callbacks.
  ///
  /// Only non-null arguments are applied, except when [clearPayloadDecoder]
  /// is `true`, which explicitly sets [payloadDecoder] to `null`.
  void update({
    DecoderCallback? decoder,
    EncoderCallback? encoder,
    PayloadDecoderCallback? payloadDecoder,
    bool clearPayloadDecoder = false,
  }) {
    if (decoder != null) _decoder = decoder;
    if (encoder != null) _encoder = encoder;
    if (clearPayloadDecoder) {
      _payloadDecoder = null;
    } else if (payloadDecoder != null) {
      _payloadDecoder = payloadDecoder;
    }
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  /// Returns a new [MessageSerializer] with the given overrides applied.
  ///
  /// The receiver is not modified.
  MessageSerializer copyWith({
    String? name,
    DecoderCallback? decoder,
    EncoderCallback? encoder,
    PayloadDecoderCallback? payloadDecoder,
    bool clearPayloadDecoder = false,
  }) =>
      MessageSerializer(
        name: name ?? this.name,
        decoder: decoder ?? _decoder,
        encoder: encoder ?? _encoder,
        payloadDecoder:
            clearPayloadDecoder ? null : (payloadDecoder ?? _payloadDecoder),
      );

  // ── Encode / decode ───────────────────────────────────────────────────────

  /// Encodes [message] for transmission over the WebSocket.
  ///
  /// Messages with a [Uint8List] payload use the binary frame format via
  /// [BinaryDecoder]; all others are encoded via the current [encoder].
  dynamic encode(Message message) {
    if (message.payload is Uint8List) {
      return BinaryDecoder.binaryEncode(message);
    }
    return _encoder(message.encode());
  }

  /// Decodes a raw WebSocket frame into a [Message].
  ///
  /// [rawData] must be a [String] (JSON / text path) or a [Uint8List]
  /// (binary path). Any other type throws [ArgumentError].
  Message decode(dynamic rawData) {
    if (rawData is String) {
      return Message.fromJson(_decoder(rawData) as List<dynamic>);
    }

    if (rawData is Uint8List) {
      final raw = BinaryDecoder.binaryDecode(rawData);
      return Message(
        joinRef: raw['join_ref'] as String?,
        ref: raw['ref'] as String?,
        topic: raw['topic'] as String?,
        event: PhoenixChannelEvent.custom(raw['event'] as String),
        payload: _decodePayload(raw['payload']),
      );
    }

    throw ArgumentError(
      'rawData must be a String or Uint8List, got ${rawData.runtimeType}',
    );
  }

  @override
  String toString() => 'MessageSerializer(name: $name)';

  // ── Private ───────────────────────────────────────────────────────────────

  dynamic _decodePayload(dynamic payload) {
    if (_payloadDecoder == null || payload is! Uint8List) return payload;
    final decoded = _payloadDecoder!(payload);
    if (decoded is Map) return MapUtils.deepConvertToStringDynamic(decoded);
    if (decoded is Uint8List) return decoded;
    return <String, dynamic>{'data': decoded};
  }
}
