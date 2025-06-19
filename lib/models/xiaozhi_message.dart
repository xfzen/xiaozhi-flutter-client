import 'dart:convert';
import 'dart:io';

/// 小智消息类型枚举
enum XiaozhiMessageType {
  hello,
  start,
  listen,
  speak,
  abort,
  tts,
  stt,
  emotion,
  voiceMute,
  voiceUnmute,
}

/// 音频参数
class AudioParams {
  final String format;
  final int sampleRate;
  final int channels;
  final int frameDuration;

  const AudioParams({
    required this.format,
    required this.sampleRate,
    required this.channels,
    required this.frameDuration,
  });

  Map<String, dynamic> toJson() => {
    'format': format,
    'sample_rate': sampleRate,
    'channels': channels,
    'frame_duration': frameDuration,
  };

  factory AudioParams.fromJson(Map<String, dynamic> json) => AudioParams(
    format: json['format'],
    sampleRate: json['sample_rate'],
    channels: json['channels'],
    frameDuration: json['frame_duration'],
  );

  /// 获取平台默认音频参数
  static AudioParams getDefault() {
    return AudioParams(
      format: Platform.isMacOS ? 'pcm16' : 'opus',
      sampleRate: 16000,
      channels: 1,
      frameDuration: 60,
    );
  }
}

/// 监听状态枚举
enum ListenState { start, stop, detect }

/// 说话状态枚举
enum SpeakState { start, stop }

/// TTS状态枚举
enum TtsState { sentenceStart, sentenceEnd }

/// 模式枚举
enum Mode { auto, manual }

/// 小智消息基类
abstract class XiaozhiMessage {
  final XiaozhiMessageType type;
  final String? sessionId;

  const XiaozhiMessage({required this.type, this.sessionId});

  /// 转换为JSON字符串
  String toJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  /// 转换为Map
  Map<String, dynamic> toJson();

  /// 从JSON创建消息
  static XiaozhiMessage fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) {
      throw ArgumentError('Message type is required');
    }

    final sessionId = json['session_id'] as String?;

    switch (typeStr) {
      case 'hello':
        return HelloMessage.fromJson(json);
      case 'start':
        return StartMessage.fromJson(json);
      case 'listen':
        return ListenMessage.fromJson(json);
      case 'speak':
        return SpeakMessage.fromJson(json);
      case 'abort':
        return AbortMessage.fromJson(json);
      case 'tts':
        return TtsMessage.fromJson(json);
      case 'stt':
        return SttMessage.fromJson(json);
      case 'emotion':
        return EmotionMessage.fromJson(json);
      case 'voice_mute':
      case 'voice_unmute':
        return VoiceControlMessage.fromJson(json);
      default:
        return UnknownMessage(
          typeString: typeStr,
          sessionId: sessionId,
          rawData: json,
        );
    }
  }

  /// 获取消息类型字符串
  String get typeString {
    switch (type) {
      case XiaozhiMessageType.hello:
        return 'hello';
      case XiaozhiMessageType.start:
        return 'start';
      case XiaozhiMessageType.listen:
        return 'listen';
      case XiaozhiMessageType.speak:
        return 'speak';
      case XiaozhiMessageType.abort:
        return 'abort';
      case XiaozhiMessageType.tts:
        return 'tts';
      case XiaozhiMessageType.stt:
        return 'stt';
      case XiaozhiMessageType.emotion:
        return 'emotion';
      case XiaozhiMessageType.voiceMute:
        return 'voice_mute';
      case XiaozhiMessageType.voiceUnmute:
        return 'voice_unmute';
    }
  }
}

/// Hello消息
class HelloMessage extends XiaozhiMessage {
  final int version;
  final String transport;
  final AudioParams audioParams;

  const HelloMessage({
    this.version = 1,
    this.transport = 'websocket',
    required this.audioParams,
    String? sessionId,
  }) : super(type: XiaozhiMessageType.hello, sessionId: sessionId);

  /// 创建默认Hello消息
  factory HelloMessage.create({String? sessionId}) {
    return HelloMessage(
      audioParams: AudioParams.getDefault(),
      sessionId: sessionId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': typeString,
      'version': version,
      'transport': transport,
      'audio_params': audioParams.toJson(),
    };

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory HelloMessage.fromJson(Map<String, dynamic> json) {
    return HelloMessage(
      version: json['version'] ?? 1,
      transport: json['transport'] ?? 'websocket',
      audioParams: AudioParams.fromJson(json['audio_params']),
      sessionId: json['session_id'],
    );
  }
}

/// Start消息
class StartMessage extends XiaozhiMessage {
  final Mode mode;
  final AudioParams? audioParams;

  const StartMessage({required this.mode, this.audioParams, String? sessionId})
    : super(type: XiaozhiMessageType.start, sessionId: sessionId);

  /// 创建默认Start消息
  factory StartMessage.create({Mode mode = Mode.auto, String? sessionId}) {
    return StartMessage(
      mode: mode,
      audioParams: AudioParams.getDefault(),
      sessionId: sessionId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': typeString, 'mode': mode.name};

    if (audioParams != null) {
      json['audio_params'] = audioParams!.toJson();
    }

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory StartMessage.fromJson(Map<String, dynamic> json) {
    return StartMessage(
      mode: Mode.values.byName(json['mode'] ?? 'auto'),
      audioParams:
          json['audio_params'] != null
              ? AudioParams.fromJson(json['audio_params'])
              : null,
      sessionId: json['session_id'],
    );
  }
}

/// Listen消息
class ListenMessage extends XiaozhiMessage {
  final ListenState state;
  final Mode mode;
  final String? text;
  final String? source;

  const ListenMessage({
    required this.state,
    required this.mode,
    this.text,
    this.source,
    String? sessionId,
  }) : super(type: XiaozhiMessageType.listen, sessionId: sessionId);

  /// 创建语音监听消息
  factory ListenMessage.voiceStart({
    Mode mode = Mode.auto,
    required String sessionId,
  }) {
    return ListenMessage(
      state: ListenState.start,
      mode: mode,
      sessionId: sessionId,
    );
  }

  /// 创建语音停止消息
  factory ListenMessage.voiceStop({
    Mode mode = Mode.auto,
    required String sessionId,
  }) {
    return ListenMessage(
      state: ListenState.stop,
      mode: mode,
      sessionId: sessionId,
    );
  }

  /// 创建文本消息
  factory ListenMessage.text({required String text, String? sessionId}) {
    return ListenMessage(
      state: ListenState.detect,
      mode: Mode.auto,
      text: text,
      source: 'text',
      sessionId: sessionId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': typeString,
      'state': state.name,
      'mode': mode.name,
    };

    if (text != null) {
      json['text'] = text;
    }

    if (source != null) {
      json['source'] = source;
    }

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory ListenMessage.fromJson(Map<String, dynamic> json) {
    return ListenMessage(
      state: ListenState.values.byName(json['state'] ?? 'start'),
      mode: Mode.values.byName(json['mode'] ?? 'auto'),
      text: json['text'],
      source: json['source'],
      sessionId: json['session_id'],
    );
  }
}

/// Speak消息
class SpeakMessage extends XiaozhiMessage {
  final SpeakState state;
  final Mode mode;

  const SpeakMessage({
    required this.state,
    required this.mode,
    String? sessionId,
  }) : super(type: XiaozhiMessageType.speak, sessionId: sessionId);

  /// 创建开始说话消息
  factory SpeakMessage.start({Mode mode = Mode.auto, String? sessionId}) {
    return SpeakMessage(
      state: SpeakState.start,
      mode: mode,
      sessionId: sessionId,
    );
  }

  /// 创建停止说话消息
  factory SpeakMessage.stop({Mode mode = Mode.auto, String? sessionId}) {
    return SpeakMessage(
      state: SpeakState.stop,
      mode: mode,
      sessionId: sessionId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': typeString,
      'state': state.name,
      'mode': mode.name,
    };

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory SpeakMessage.fromJson(Map<String, dynamic> json) {
    return SpeakMessage(
      state: SpeakState.values.byName(json['state'] ?? 'start'),
      mode: Mode.values.byName(json['mode'] ?? 'auto'),
      sessionId: json['session_id'],
    );
  }
}

/// Abort消息
class AbortMessage extends XiaozhiMessage {
  final String? reason;

  const AbortMessage({this.reason, String? sessionId})
    : super(type: XiaozhiMessageType.abort, sessionId: sessionId);

  /// 创建用户打断消息
  factory AbortMessage.userInterrupt({required String sessionId}) {
    return AbortMessage(reason: 'user_interrupt', sessionId: sessionId);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': typeString};

    if (reason != null) {
      json['reason'] = reason;
    }

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory AbortMessage.fromJson(Map<String, dynamic> json) {
    return AbortMessage(reason: json['reason'], sessionId: json['session_id']);
  }
}

/// TTS消息
class TtsMessage extends XiaozhiMessage {
  final TtsState state;
  final String text;

  const TtsMessage({required this.state, required this.text, String? sessionId})
    : super(type: XiaozhiMessageType.tts, sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': typeString,
      'state': _stateToString(state),
      'text': text,
    };

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory TtsMessage.fromJson(Map<String, dynamic> json) {
    return TtsMessage(
      state: _stringToTtsState(json['state'] ?? ''),
      text: json['text'] ?? '',
      sessionId: json['session_id'],
    );
  }

  static String _stateToString(TtsState state) {
    switch (state) {
      case TtsState.sentenceStart:
        return 'sentence_start';
      case TtsState.sentenceEnd:
        return 'sentence_end';
    }
  }

  static TtsState _stringToTtsState(String state) {
    switch (state) {
      case 'sentence_start':
        return TtsState.sentenceStart;
      case 'sentence_end':
        return TtsState.sentenceEnd;
      default:
        return TtsState.sentenceStart;
    }
  }
}

/// STT消息
class SttMessage extends XiaozhiMessage {
  final String text;

  const SttMessage({required this.text, String? sessionId})
    : super(type: XiaozhiMessageType.stt, sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': typeString, 'text': text};

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory SttMessage.fromJson(Map<String, dynamic> json) {
    return SttMessage(text: json['text'] ?? '', sessionId: json['session_id']);
  }
}

/// Emotion消息
class EmotionMessage extends XiaozhiMessage {
  final String emotion;

  const EmotionMessage({required this.emotion, String? sessionId})
    : super(type: XiaozhiMessageType.emotion, sessionId: sessionId);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': typeString, 'emotion': emotion};

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory EmotionMessage.fromJson(Map<String, dynamic> json) {
    return EmotionMessage(
      emotion: json['emotion'] ?? '',
      sessionId: json['session_id'],
    );
  }
}

/// 语音控制消息
class VoiceControlMessage extends XiaozhiMessage {
  const VoiceControlMessage({
    required XiaozhiMessageType type,
    String? sessionId,
  }) : super(type: type, sessionId: sessionId);

  /// 创建静音消息
  factory VoiceControlMessage.mute({String? sessionId}) {
    return VoiceControlMessage(
      type: XiaozhiMessageType.voiceMute,
      sessionId: sessionId,
    );
  }

  /// 创建取消静音消息
  factory VoiceControlMessage.unmute({String? sessionId}) {
    return VoiceControlMessage(
      type: XiaozhiMessageType.voiceUnmute,
      sessionId: sessionId,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': typeString};

    if (sessionId != null) {
      json['session_id'] = sessionId;
    }

    return json;
  }

  factory VoiceControlMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type =
        typeStr == 'voice_mute'
            ? XiaozhiMessageType.voiceMute
            : XiaozhiMessageType.voiceUnmute;

    return VoiceControlMessage(type: type, sessionId: json['session_id']);
  }
}

/// 未知消息类型
class UnknownMessage extends XiaozhiMessage {
  final String typeString;
  final Map<String, dynamic> rawData;

  const UnknownMessage({
    required this.typeString,
    required this.rawData,
    String? sessionId,
  }) : super(type: XiaozhiMessageType.hello, sessionId: sessionId); // 使用任意类型

  @override
  Map<String, dynamic> toJson() => rawData;
}

/// 消息工厂类
class XiaozhiMessageFactory {
  /// 创建Hello消息
  static HelloMessage createHello({String? sessionId}) {
    return HelloMessage.create(sessionId: sessionId);
  }

  /// 创建Start消息
  static StartMessage createStart({Mode mode = Mode.auto, String? sessionId}) {
    return StartMessage.create(mode: mode, sessionId: sessionId);
  }

  /// 创建开始语音监听消息
  static ListenMessage createVoiceListenStart({
    Mode mode = Mode.auto,
    required String sessionId,
  }) {
    return ListenMessage.voiceStart(mode: mode, sessionId: sessionId);
  }

  /// 创建停止语音监听消息
  static ListenMessage createVoiceListenStop({
    Mode mode = Mode.auto,
    required String sessionId,
  }) {
    return ListenMessage.voiceStop(mode: mode, sessionId: sessionId);
  }

  /// 创建文本消息
  static ListenMessage createTextMessage({
    required String text,
    String? sessionId,
  }) {
    return ListenMessage.text(text: text, sessionId: sessionId);
  }

  /// 创建开始说话消息
  static SpeakMessage createSpeakStart({
    Mode mode = Mode.auto,
    String? sessionId,
  }) {
    return SpeakMessage.start(mode: mode, sessionId: sessionId);
  }

  /// 创建停止说话消息
  static SpeakMessage createSpeakStop({
    Mode mode = Mode.auto,
    String? sessionId,
  }) {
    return SpeakMessage.stop(mode: mode, sessionId: sessionId);
  }

  /// 创建用户打断消息
  static AbortMessage createUserInterrupt({required String sessionId}) {
    return AbortMessage.userInterrupt(sessionId: sessionId);
  }

  /// 创建静音消息
  static VoiceControlMessage createMute({String? sessionId}) {
    return VoiceControlMessage.mute(sessionId: sessionId);
  }

  /// 创建取消静音消息
  static VoiceControlMessage createUnmute({String? sessionId}) {
    return VoiceControlMessage.unmute(sessionId: sessionId);
  }
}
