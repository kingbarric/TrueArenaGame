/// Baseline mirror of `shared/contract/envelope.schema.json` (Architecture §3.2).
/// Hand-maintained until the codegen tool lands; see shared/contract/README.md.
library;

enum MessageType {
  hello('HELLO'),
  readySet('READY_SET'),
  configSet('CONFIG_SET'),
  gameStart('GAME_START'),
  playerAction('PLAYER_ACTION'),
  hostControl('HOST_CONTROL'),
  ping('PING'),
  snapshot('SNAPSHOT'),
  event('EVENT'),
  phase('PHASE'),
  error('ERROR'),
  pong('PONG');

  const MessageType(this.wire);

  final String wire;

  static MessageType fromWire(String value) =>
      MessageType.values.firstWhere((t) => t.wire == value,
          orElse: () => throw ArgumentError('unknown message type: $value'));
}

class Envelope {
  const Envelope({
    required this.type,
    required this.ts,
    this.v = 1,
    this.seq,
    this.payload = const {},
  });

  final int v;
  final MessageType type;
  final int? seq;
  final int ts;
  final Map<String, dynamic> payload;

  factory Envelope.fromJson(Map<String, dynamic> json) => Envelope(
        v: json['v'] as int? ?? 1,
        type: MessageType.fromWire(json['type'] as String),
        seq: (json['seq'] as num?)?.toInt(),
        ts: (json['ts'] as num).toInt(),
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'v': v,
        'type': type.wire,
        if (seq != null) 'seq': seq,
        'ts': ts,
        'payload': payload,
      };

  static Envelope create(MessageType type, Map<String, dynamic> payload) =>
      Envelope(
        type: type,
        ts: DateTime.now().millisecondsSinceEpoch,
        payload: payload,
      );
}
