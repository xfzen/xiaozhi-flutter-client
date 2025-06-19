import 'dart:async';
import 'dart:convert';
import '../models/xiaozhi_message.dart';
import 'xiaozhi_websocket_manager.dart';

/// 消息发送结果
class MessageSendResult {
  final bool success;
  final String? error;
  final XiaozhiMessage? message;

  const MessageSendResult({required this.success, this.error, this.message});

  factory MessageSendResult.success(XiaozhiMessage message) {
    return MessageSendResult(success: true, message: message);
  }

  factory MessageSendResult.failure(String error) {
    return MessageSendResult(success: false, error: error);
  }
}

/// 消息接收事件
class MessageReceiveEvent {
  final XiaozhiMessage message;
  final DateTime timestamp;

  MessageReceiveEvent({required this.message, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

/// 消息管理器事件类型
enum MessageManagerEventType {
  connected,
  disconnected,
  messageSent,
  messageReceived,
  binaryMessage,
  error,
}

/// 消息管理器事件
class MessageManagerEvent {
  final MessageManagerEventType type;
  final dynamic data;
  final DateTime timestamp;

  MessageManagerEvent({required this.type, this.data, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

/// 消息管理器监听器
typedef MessageManagerListener = void Function(MessageManagerEvent event);

/// 小智消息管理器
///
/// 这个类负责统一管理消息的构造、发送、接收和解析
/// 提供类型安全的消息操作接口，简化上层业务逻辑
class XiaozhiMessageManager {
  static const String TAG = "XiaozhiMessageManager";

  final XiaozhiWebSocketManager _webSocketManager;
  final List<MessageManagerListener> _listeners = [];
  final StreamController<MessageReceiveEvent> _messageController =
      StreamController<MessageReceiveEvent>.broadcast();

  String? _currentSessionId;

  /// 构造函数
  XiaozhiMessageManager(this._webSocketManager) {
    _webSocketManager.addListener(_onWebSocketEvent);
  }

  /// 添加监听器
  void addListener(MessageManagerListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除监听器
  void removeListener(MessageManagerListener listener) {
    _listeners.remove(listener);
  }

  /// 获取消息流
  Stream<MessageReceiveEvent> get messageStream => _messageController.stream;

  /// 设置会话ID
  void setSessionId(String? sessionId) {
    _currentSessionId = sessionId;
    print('$TAG: 会话ID更新为: $sessionId');
  }

  /// 获取当前会话ID
  String? get sessionId => _currentSessionId;

  /// 发送消息的通用方法
  Future<MessageSendResult> sendMessage(XiaozhiMessage message) async {
    try {
      if (!_webSocketManager.isConnected) {
        return MessageSendResult.failure('WebSocket未连接');
      }

      // 如果消息没有session_id且我们有当前session_id，则添加
      XiaozhiMessage messageToSend = message;
      if (message.sessionId == null && _currentSessionId != null) {
        messageToSend = _addSessionIdToMessage(message, _currentSessionId!);
      }

      final jsonString = messageToSend.toJsonString();
      print('$TAG: 发送消息:\n$jsonString');

      _webSocketManager.sendMessage(jsonString);

      // 分发发送事件
      _dispatchEvent(
        MessageManagerEvent(
          type: MessageManagerEventType.messageSent,
          data: messageToSend,
        ),
      );

      return MessageSendResult.success(messageToSend);
    } catch (e) {
      final error = '发送消息失败: $e';
      print('$TAG: $error');

      _dispatchEvent(
        MessageManagerEvent(type: MessageManagerEventType.error, data: error),
      );

      return MessageSendResult.failure(error);
    }
  }

  /// 发送Hello消息
  Future<MessageSendResult> sendHello() async {
    final message = XiaozhiMessageFactory.createHello(
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送Start消息
  Future<MessageSendResult> sendStart({Mode mode = Mode.auto}) async {
    final message = XiaozhiMessageFactory.createStart(
      mode: mode,
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送开始语音监听消息
  Future<MessageSendResult> sendVoiceListenStart({
    Mode mode = Mode.auto,
  }) async {
    if (_currentSessionId == null) {
      return MessageSendResult.failure('会话ID为空，无法开始语音监听');
    }

    final message = XiaozhiMessageFactory.createVoiceListenStart(
      mode: mode,
      sessionId: _currentSessionId!,
    );
    return sendMessage(message);
  }

  /// 发送停止语音监听消息
  Future<MessageSendResult> sendVoiceListenStop({Mode mode = Mode.auto}) async {
    if (_currentSessionId == null) {
      return MessageSendResult.failure('会话ID为空，无法停止语音监听');
    }

    final message = XiaozhiMessageFactory.createVoiceListenStop(
      mode: mode,
      sessionId: _currentSessionId!,
    );
    return sendMessage(message);
  }

  /// 发送文本消息
  Future<MessageSendResult> sendTextMessage(String text) async {
    final message = XiaozhiMessageFactory.createTextMessage(
      text: text,
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送开始说话消息
  Future<MessageSendResult> sendSpeakStart({Mode mode = Mode.auto}) async {
    final message = XiaozhiMessageFactory.createSpeakStart(
      mode: mode,
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送停止说话消息
  Future<MessageSendResult> sendSpeakStop({Mode mode = Mode.auto}) async {
    final message = XiaozhiMessageFactory.createSpeakStop(
      mode: mode,
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送用户打断消息
  Future<MessageSendResult> sendUserInterrupt() async {
    if (_currentSessionId == null) {
      return MessageSendResult.failure('会话ID为空，无法发送打断消息');
    }

    final message = XiaozhiMessageFactory.createUserInterrupt(
      sessionId: _currentSessionId!,
    );
    return sendMessage(message);
  }

  /// 发送静音消息
  Future<MessageSendResult> sendMute() async {
    final message = XiaozhiMessageFactory.createMute(
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 发送取消静音消息
  Future<MessageSendResult> sendUnmute() async {
    final message = XiaozhiMessageFactory.createUnmute(
      sessionId: _currentSessionId,
    );
    return sendMessage(message);
  }

  /// 处理WebSocket事件
  void _onWebSocketEvent(XiaozhiEvent event) {
    switch (event.type) {
      case XiaozhiEventType.connected:
        print('$TAG: WebSocket已连接');
        _dispatchEvent(
          MessageManagerEvent(type: MessageManagerEventType.connected),
        );
        break;

      case XiaozhiEventType.disconnected:
        print('$TAG: WebSocket已断开');
        _dispatchEvent(
          MessageManagerEvent(type: MessageManagerEventType.disconnected),
        );
        break;

      case XiaozhiEventType.message:
        _handleTextMessage(event.data as String);
        break;

      case XiaozhiEventType.error:
        print('$TAG: WebSocket错误: ${event.data}');
        _dispatchEvent(
          MessageManagerEvent(
            type: MessageManagerEventType.error,
            data: event.data,
          ),
        );
        break;

      case XiaozhiEventType.binaryMessage:
        // 分发二进制消息事件，让上层处理
        _dispatchEvent(
          MessageManagerEvent(
            type: MessageManagerEventType.binaryMessage,
            data: event.data,
          ),
        );
        break;
    }
  }

  /// 处理文本消息
  void _handleTextMessage(String messageText) {
    try {
      print('$TAG: 收到消息:\n${_prettyPrintJson(messageText)}');

      final jsonData = jsonDecode(messageText) as Map<String, dynamic>;
      final message = XiaozhiMessage.fromJson(jsonData);

      // 如果收到的消息包含session_id，更新当前session_id
      if (message.sessionId != null && message.sessionId != _currentSessionId) {
        print('$TAG: 从服务器消息中更新会话ID: ${message.sessionId}');
        _currentSessionId = message.sessionId;
      }

      // 创建接收事件
      final receiveEvent = MessageReceiveEvent(message: message);

      // 分发到流
      _messageController.add(receiveEvent);

      // 分发事件
      _dispatchEvent(
        MessageManagerEvent(
          type: MessageManagerEventType.messageReceived,
          data: receiveEvent,
        ),
      );
    } catch (e) {
      final error = '解析消息失败: $e, 原始消息: $messageText';
      print('$TAG: $error');

      _dispatchEvent(
        MessageManagerEvent(type: MessageManagerEventType.error, data: error),
      );
    }
  }

  /// 添加session_id到消息
  XiaozhiMessage _addSessionIdToMessage(
    XiaozhiMessage message,
    String sessionId,
  ) {
    // 这里需要根据消息类型重新创建消息，因为消息对象是不可变的
    switch (message.type) {
      case XiaozhiMessageType.hello:
        final hello = message as HelloMessage;
        return HelloMessage(
          version: hello.version,
          transport: hello.transport,
          audioParams: hello.audioParams,
          sessionId: sessionId,
        );

      case XiaozhiMessageType.start:
        final start = message as StartMessage;
        return StartMessage(
          mode: start.mode,
          audioParams: start.audioParams,
          sessionId: sessionId,
        );

      case XiaozhiMessageType.listen:
        final listen = message as ListenMessage;
        return ListenMessage(
          state: listen.state,
          mode: listen.mode,
          text: listen.text,
          source: listen.source,
          sessionId: sessionId,
        );

      case XiaozhiMessageType.speak:
        final speak = message as SpeakMessage;
        return SpeakMessage(
          state: speak.state,
          mode: speak.mode,
          sessionId: sessionId,
        );

      case XiaozhiMessageType.abort:
        final abort = message as AbortMessage;
        return AbortMessage(reason: abort.reason, sessionId: sessionId);

      case XiaozhiMessageType.voiceMute:
        return VoiceControlMessage.mute(sessionId: sessionId);

      case XiaozhiMessageType.voiceUnmute:
        return VoiceControlMessage.unmute(sessionId: sessionId);

      default:
        // 对于其他类型，返回原消息
        return message;
    }
  }

  /// 分发事件
  void _dispatchEvent(MessageManagerEvent event) {
    for (final listener in _listeners) {
      try {
        listener(event);
      } catch (e) {
        print('$TAG: 事件监听器处理失败: $e');
      }
    }
  }

  /// 格式化JSON字符串用于打印
  String _prettyPrintJson(String jsonString) {
    try {
      final jsonObject = jsonDecode(jsonString);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(jsonObject);
    } catch (e) {
      // 如果解析失败，返回原字符串
      return jsonString;
    }
  }

  /// 销毁资源
  void dispose() {
    _webSocketManager.removeListener(_onWebSocketEvent);
    _messageController.close();
    _listeners.clear();
    print('$TAG: 资源已释放');
  }
}
