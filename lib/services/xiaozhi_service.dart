import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/xiaozhi_websocket_manager.dart';
import '../services/xiaozhi_message_manager.dart';
import '../models/xiaozhi_message.dart';
import '../utils/audio_util.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 小智服务事件类型
enum XiaozhiServiceEventType {
  connected,
  disconnected,
  textMessage,
  audioData,
  error,
  voiceCallStart,
  voiceCallEnd,
  userMessage,
}

/// 小智服务事件
class XiaozhiServiceEvent {
  final XiaozhiServiceEventType type;
  final dynamic data;

  XiaozhiServiceEvent(this.type, this.data);
}

/// 小智服务监听器
typedef XiaozhiServiceListener = void Function(XiaozhiServiceEvent event);

/// 消息监听器
typedef MessageListener = void Function(dynamic message);

/// 全局语音通话状态缓存
class VoiceCallStateCache {
  static final VoiceCallStateCache _instance = VoiceCallStateCache._internal();
  factory VoiceCallStateCache() => _instance;
  VoiceCallStateCache._internal();

  bool _isVoiceCallActive = false;
  bool _hasStartedCall = false;
  String? _pendingSessionId;

  bool get isVoiceCallActive => _isVoiceCallActive;
  bool get hasStartedCall => _hasStartedCall;
  String? get pendingSessionId => _pendingSessionId;

  void setVoiceCallActive(bool active) {
    _isVoiceCallActive = active;
    print('VoiceCallStateCache: 设置语音通话状态为 $active');
  }

  void setCallStarted(bool started) {
    _hasStartedCall = started;
    print('VoiceCallStateCache: 设置通话开始状态为 $started');
  }

  void setPendingSessionId(String? sessionId) {
    _pendingSessionId = sessionId;
    print('VoiceCallStateCache: 设置待处理会话ID为 $sessionId');
  }

  void reset() {
    _isVoiceCallActive = false;
    _hasStartedCall = false;
    _pendingSessionId = null;
    print('VoiceCallStateCache: 重置所有状态');
  }

  bool shouldStartRecording() {
    return _isVoiceCallActive && !_hasStartedCall;
  }
}

/// 小智服务
class XiaozhiService {
  static const String TAG = "XiaozhiService";
  static const String DEFAULT_SERVER = "wss://ws.xiaozhi.ai";

  final String websocketUrl;
  final String macAddress;
  final String token;
  String? _sessionId; // 会话ID将由服务器提供

  XiaozhiWebSocketManager? _webSocketManager;
  XiaozhiMessageManager? _messageManager;
  bool _isConnected = false;
  bool _isMuted = false;
  final List<XiaozhiServiceListener> _listeners = [];
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _messageStreamSubscription;
  MessageListener? _messageListener;

  // 使用全局状态缓存
  final VoiceCallStateCache _stateCache = VoiceCallStateCache();

  // ⭐ 新增：按住说话模式的独立状态管理
  bool _isPushToTalkMode = false;
  bool _isTtsPlaying = false; // ⭐ 新增：TTS播放状态标志

  /// 构造函数 - 移除单例模式，允许创建多个实例
  XiaozhiService({
    required this.websocketUrl,
    required this.macAddress,
    required this.token,
    String? sessionId,
  }) {
    _sessionId = sessionId;
    print('$TAG: 创建新的XiaozhiService实例');
    print('  WebSocket URL: $websocketUrl');
    print('  MAC地址: $macAddress');
    print('  Token: $token');
    print('  会话ID: $_sessionId');
    _init();
  }

  /// 切换到语音通话模式
  Future<void> switchToVoiceCallMode() async {
    // 如果已经在语音通话模式，直接返回
    if (_stateCache.isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到语音通话模式');

      // 重要：先设置语音通话模式为true，再建立连接
      // 这样确保在收到hello消息时，条件检查能够通过
      _stateCache.setVoiceCallActive(true);
      _stateCache.setCallStarted(false);

      // 建立WebSocket连接
      if (!_isConnected) {
        await connectVoiceCall();
        _isConnected = true; // 手动设置连接状态
      }

      // 简化初始化流程，确保干净状态
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      print('$TAG: 已切换到语音通话模式');
    } catch (e) {
      print('$TAG: 切换到语音通话模式失败: $e');
      // 如果失败，重置状态
      _stateCache.reset();
      rethrow;
    }
  }

  /// 切换到普通聊天模式
  Future<void> switchToChatMode() async {
    // 如果已经在普通聊天模式，直接返回
    if (!_stateCache.isVoiceCallActive) return;

    try {
      print('$TAG: 正在切换到普通聊天模式');

      // 停止语音通话相关的活动
      await stopListeningCall();

      // 确保播放器停止
      await AudioUtil.stopPlaying();

      _stateCache.reset();
      print('$TAG: 已切换到普通聊天模式');
    } catch (e) {
      print('$TAG: 切换到普通聊天模式失败: $e');
      _stateCache.reset();
    }
  }

  /// 初始化
  Future<void> _init() async {
    // 使用配置中的MAC地址作为设备ID
    print('$TAG: 初始化完成，使用MAC地址作为设备ID: $macAddress');

    // 初始化WebSocket管理器，启用 token
    _webSocketManager = XiaozhiWebSocketManager(
      deviceId: macAddress,
      enableToken: true,
    );

    // 初始化消息管理器
    _initMessageManager();

    // 初始化音频工具
    await AudioUtil.initRecorder();
    await AudioUtil.initPlayer();
  }

  /// 初始化消息管理器
  void _initMessageManager() {
    if (_webSocketManager == null) return;

    _messageManager = XiaozhiMessageManager(_webSocketManager!);
    _messageManager!.setSessionId(_sessionId);

    // 监听消息流
    _messageStreamSubscription = _messageManager!.messageStream.listen(
      _handleMessageReceiveEvent,
    );

    // 监听消息管理器事件
    _messageManager!.addListener(_handleMessageManagerEvent);

    print('$TAG: 消息管理器初始化完成');
  }

  /// 处理消息接收事件
  void _handleMessageReceiveEvent(MessageReceiveEvent event) {
    final message = event.message;

    // 调用传统的消息监听器（向后兼容）
    if (_messageListener != null) {
      _messageListener!(message.toJson());
    }

    // 根据消息类型分发事件
    switch (message.type) {
      case XiaozhiMessageType.hello:
        // 处理hello消息
        if (!_isConnected) {
          _isConnected = true;
          print('$TAG: 收到hello消息，连接已建立');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.connected, null),
          );
        }

        // 添加详细的调试信息
        print('$TAG: 执行hello消息处理逻辑');
        print(
          '$TAG: 当前状态 - isVoiceCallActive: ${_stateCache.isVoiceCallActive}, hasStartedCall: ${_stateCache.hasStartedCall}',
        );

        if (_stateCache.shouldStartRecording()) {
          _stateCache.setCallStarted(true);
          print('$TAG: 条件满足，准备开始语音通话录音...');

          // 异步开始语音通话录音，避免阻塞消息处理
          Future.microtask(() async {
            try {
              print('$TAG: 正在执行startListeningCall()...');
              await startListeningCall();
              print('$TAG: 语音通话录音已成功开始');
            } catch (error) {
              print('$TAG: 开始录音失败: $error');
              // 重置状态，允许重试
              _stateCache.setCallStarted(false);
            }
          });
        } else {
          print('$TAG: 不满足开始录音条件');
        }
        break;

      case XiaozhiMessageType.start:
        // 收到start响应后，如果是语音通话模式，开始录音
        if (_stateCache.isVoiceCallActive) {
          _sendListenMessage();
        }
        break;

      case XiaozhiMessageType.tts:
        final ttsMessage = message as TtsMessage;
        if (ttsMessage.state == TtsState.sentenceStart &&
            ttsMessage.text.isNotEmpty) {
          print('$TAG: 收到TTS句子: ${ttsMessage.text}');
          _dispatchEvent(
            XiaozhiServiceEvent(
              XiaozhiServiceEventType.textMessage,
              ttsMessage.text,
            ),
          );
        }
        break;

      case XiaozhiMessageType.stt:
        final sttMessage = message as SttMessage;
        if (sttMessage.text.isNotEmpty) {
          print('$TAG: 收到语音识别结果: ${sttMessage.text}');
          _dispatchEvent(
            XiaozhiServiceEvent(
              XiaozhiServiceEventType.userMessage,
              sttMessage.text,
            ),
          );
        }
        break;

      case XiaozhiMessageType.emotion:
        final emotionMessage = message as EmotionMessage;
        if (emotionMessage.emotion.isNotEmpty) {
          print('$TAG: 收到表情消息: ${emotionMessage.emotion}');
          _dispatchEvent(
            XiaozhiServiceEvent(
              XiaozhiServiceEventType.textMessage,
              '表情: ${emotionMessage.emotion}',
            ),
          );
        }
        break;

      default:
        // ⭐ 修复：处理未知消息类型，特别是LLM消息
        if (message is UnknownMessage && message.typeString == 'llm') {
          final text = message.rawData['text'] as String?;
          if (text != null && text.isNotEmpty) {
            print('$TAG: 收到LLM回复: $text');
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.textMessage, text),
            );
          }
        } else {
          print('$TAG: 收到未知类型消息: ${message.type}');
        }
    }

    // 更新会话ID
    if (message.sessionId != null && message.sessionId != _sessionId) {
      _sessionId = message.sessionId;
      _messageManager?.setSessionId(_sessionId);
      print('$TAG: 更新会话ID: $_sessionId');
    }
  }

  /// 处理消息管理器事件
  void _handleMessageManagerEvent(MessageManagerEvent event) {
    switch (event.type) {
      case MessageManagerEventType.connected:
        if (!_isConnected) {
          _isConnected = true;
          print('$TAG: WebSocket连接已建立');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.connected, null),
          );
        }
        break;

      case MessageManagerEventType.disconnected:
        _isConnected = false;
        print('$TAG: WebSocket连接已断开');
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.disconnected, null),
        );
        break;

      case MessageManagerEventType.error:
        print('$TAG: 消息管理器错误: ${event.data}');
        _dispatchEvent(
          XiaozhiServiceEvent(XiaozhiServiceEventType.error, event.data),
        );
        break;

      case MessageManagerEventType.messageSent:
      case MessageManagerEventType.messageReceived:
        // 这些事件通过其他方式处理
        break;

      case MessageManagerEventType.binaryMessage:
        // 处理二进制音频数据
        final audioData = event.data as List<int>;
        _handleBinaryMessage(audioData);
        break;
    }
  }

  /// 处理二进制消息（音频数据）
  void _handleBinaryMessage(List<int> audioData) {
    if (Platform.isMacOS) {
      // macOS上直接播放PCM数据
      AudioUtil.playPcmData(Uint8List.fromList(audioData));
    } else {
      // 其他平台播放Opus数据
      AudioUtil.playOpusData(Uint8List.fromList(audioData));
    }
  }

  /// 设置消息监听器
  void setMessageListener(MessageListener? listener) {
    _messageListener = listener;
  }

  /// 添加事件监听器
  void addListener(XiaozhiServiceListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// 移除事件监听器
  void removeListener(XiaozhiServiceListener listener) {
    _listeners.remove(listener);
  }

  /// 分发事件到所有监听器
  void _dispatchEvent(XiaozhiServiceEvent event) {
    // 创建监听器列表的副本，避免并发修改异常
    final listenersCopy = List.from(_listeners);
    for (var listener in listenersCopy) {
      try {
        listener(event);
      } catch (e) {
        print('$TAG: 事件监听器执行出错: $e');
      }
    }
  }

  /// 断开小智服务连接
  Future<void> disconnect() async {
    if (!_isConnected || _webSocketManager == null) return;

    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 断开WebSocket连接
      await _webSocketManager!.disconnect();
      _webSocketManager = null;
      _isConnected = false;
    } catch (e) {
      print('$TAG: 断开连接失败: $e');
    }
  }

  /// 发送文本消息
  Future<String> sendTextMessage(String message) async {
    if (!_isConnected && _webSocketManager == null) {
      await connectVoiceCall();
    }

    try {
      // 创建一个Completer来等待响应
      final completer = Completer<String>();

      print('$TAG: 开始发送文本消息: $message');

      // 添加消息监听器，监听所有可能的回复
      void onceListener(XiaozhiServiceEvent event) {
        if (event.type == XiaozhiServiceEventType.textMessage) {
          // 忽略echo消息（即我们发送的消息）
          if (event.data == message) {
            print('$TAG: 忽略echo消息: ${event.data}');
            return;
          }

          print('$TAG: 收到服务器响应: ${event.data}');
          if (!completer.isCompleted) {
            completer.complete(event.data as String);
            removeListener(onceListener);
          }
        } else if (event.type == XiaozhiServiceEventType.error &&
            !completer.isCompleted) {
          print('$TAG: 收到错误响应: ${event.data}');
          completer.completeError(event.data.toString());
          removeListener(onceListener);
        }
      }

      // 先添加监听器，确保不会错过任何消息
      addListener(onceListener);

      // 发送文本请求
      print('$TAG: 发送文本请求: $message');
      await _messageManager!.sendTextMessage(message);

      // 设置超时，15秒比10秒更宽松一些
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          print('$TAG: 请求超时，15秒内没有收到响应');
          completer.completeError('请求超时');
          removeListener(onceListener);
        }
      });

      // 等待响应
      try {
        final result = await completer.future;
        // 取消超时定时器
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        // 取消超时定时器
        timeoutTimer.cancel();
        rethrow;
      }
    } catch (e) {
      print('$TAG: 发送消息失败: $e');
      rethrow;
    }
  }

  /// 连接语音通话
  Future<void> connectVoiceCall() async {
    try {
      // 简化流程，确保权限和音频准备就绪（仅在移动平台）
      if (Platform.isIOS || Platform.isAndroid) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          print('$TAG: 麦克风权限被拒绝');
          _dispatchEvent(
            XiaozhiServiceEvent(XiaozhiServiceEventType.error, '麦克风权限被拒绝'),
          );
          throw Exception('麦克风权限被拒绝');
        }
      } else {
        print('$TAG: 桌面平台跳过权限检查');
      }

      // 初始化音频系统
      await AudioUtil.stopPlaying();
      await AudioUtil.initRecorder();
      await AudioUtil.initPlayer();

      print('$TAG: 正在连接 $websocketUrl');
      print('$TAG: 设备ID: $macAddress');
      print('$TAG: Token启用: true');
      print('$TAG: 使用Token: $token');

      // 如果已有连接，先断开
      if (_webSocketManager != null) {
        await _webSocketManager!.disconnect();
      }

      // 使用 WebSocketManager 连接
      _webSocketManager = XiaozhiWebSocketManager(
        deviceId: macAddress,
        enableToken: true,
      );

      // 重新初始化消息管理器
      _initMessageManager();

      // 直接连接，不等待超时
      await _webSocketManager!.connect(websocketUrl, token);

      // 连接成功后等待一小段时间，让hello消息处理完成
      await Future.delayed(const Duration(milliseconds: 500));

      print('$TAG: 语音通话连接建立完成');
    } catch (e) {
      print('$TAG: 连接失败: $e');
      rethrow;
    }
  }

  /// 结束语音通话
  Future<void> disconnectVoiceCall() async {
    if (_webSocketManager == null) return;

    try {
      // 停止音频录制
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
      }

      // 停止音频播放
      await AudioUtil.stopPlaying();

      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 直接断开连接
      await disconnect();
    } catch (e) {
      // 忽略断开连接时的错误
      print('$TAG: 结束语音通话时发生错误: $e');
    }
  }

  /// 开始说话
  Future<void> startSpeaking() async {
    try {
      await _messageManager?.sendSpeakStart();
    } catch (e) {
      print('$TAG: 开始说话失败: $e');
    }
  }

  /// 停止说话
  Future<void> stopSpeaking() async {
    try {
      await _messageManager?.sendSpeakStop();
    } catch (e) {
      print('$TAG: 停止说话失败: $e');
    }
  }

  /// 发送listen消息
  void _sendListenMessage() async {
    try {
      await _messageManager?.sendVoiceListenStart();

      // 开始录音
      _stateCache.setVoiceCallActive(true);
      await AudioUtil.startRecording();
    } catch (e) {
      print('$TAG: 发送listen消息失败: $e');
      _dispatchEvent(
        XiaozhiServiceEvent(XiaozhiServiceEventType.error, '发送listen消息失败: $e'),
      );
    }
  }

  /// 开始听说（语音通话模式）
  Future<void> startListeningCall() async {
    print('$TAG: startListeningCall()方法被调用');
    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        print('$TAG: 没有会话ID，无法开始监听，等待会话ID初始化...');
        // 等待短暂时间，然后重新检查会话ID
        await Future.delayed(const Duration(milliseconds: 500));
        if (_sessionId == null) {
          print('$TAG: 会话ID仍然为空，放弃开始监听');
          throw Exception('会话ID为空，无法开始录音');
        }
      }

      print('$TAG: 使用会话ID开始录音: $_sessionId');

      // ⭐ 修复：先取消任何现有的音频流订阅，避免重复订阅
      if (_audioStreamSubscription != null) {
        print('$TAG: 检测到现有音频流订阅，先取消...');
        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = null;
      }

      // 请求麦克风权限（移动平台和桌面平台通用）
      if (Platform.isIOS || Platform.isAndroid) {
        // 移动平台权限请求
        final micStatus = await Permission.microphone.status;
        if (micStatus != PermissionStatus.granted) {
          final result = await Permission.microphone.request();
          if (result != PermissionStatus.granted) {
            print('$TAG: 麦克风权限被拒绝，状态: $result');
            final errorMessage =
                result == PermissionStatus.permanentlyDenied
                    ? '麦克风权限被永久拒绝，请在设置中启用'
                    : '麦克风权限被拒绝';
            _dispatchEvent(
              XiaozhiServiceEvent(XiaozhiServiceEventType.error, errorMessage),
            );
            throw Exception(errorMessage);
          }
        }
        print('$TAG: 麦克风权限已获取');
      } else {
        // 桌面平台通常不需要显式权限请求
        print('$TAG: 桌面平台，跳过权限请求');
      }

      // 确保音频录制器已初始化
      await AudioUtil.initRecorder();
      print('$TAG: 音频录制器初始化完成');

      // ⭐ 修复：确保之前的录音已完全停止
      if (AudioUtil.isRecording) {
        print('$TAG: 检测到录音正在进行，先停止...');
        await AudioUtil.stopRecording();
        await Future.delayed(const Duration(milliseconds: 100)); // 等待完全停止
      }

      // 开始录音
      print('$TAG: 准备开始音频录制...');
      await AudioUtil.startRecording();
      print('$TAG: 音频录制已启动，等待音频流数据...');

      // ⭐ 添加音频流状态报告
      AudioUtil.printAudioStreamReport();

      // ⭐ 修复：设置音频流订阅，增加计数器跟踪发送的数据包
      print('$TAG: 设置音频流订阅...');
      int audioPacketCount = 0;
      int lastLoggedCount = 0;
      _audioStreamSubscription = AudioUtil.audioStream.listen(
        (audioData) {
          audioPacketCount++;

          // ⭐ 合并日志：只在每10个包或重要节点时打印
          bool shouldLog =
              (audioPacketCount % 10 == 1) ||
              (audioPacketCount - lastLoggedCount > 50);

          if (shouldLog) {
            print(
              '$TAG: 🎵 处理音频包 #$audioPacketCount，长度: ${audioData.length} 字节',
            );
            lastLoggedCount = audioPacketCount;
          }

          if (_webSocketManager != null && _webSocketManager!.isConnected) {
            _webSocketManager!.sendBinaryMessage(audioData);
            if (shouldLog) {
              print('$TAG: ✅ 音频包 #$audioPacketCount 已发送到WebSocket');
            }
          } else {
            print('$TAG: ❌ WebSocket未连接，音频包 #$audioPacketCount 发送失败');
          }
        },
        onError: (error) {
          print('$TAG: ❌ 音频流错误: $error');
          // 重新开始录音
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (_stateCache.isVoiceCallActive) {
              print('$TAG: 尝试重新开始录音...');
              await startListeningCall();
            }
          });
        },
        onDone: () {
          print('$TAG: 🔚 音频流结束，发送了总计 $audioPacketCount 个音频包');
        },
      );

      print('$TAG: 音频流订阅已设置');

      // 发送开始监听命令
      print('$TAG: 发送语音监听开始命令...');
      await _messageManager?.sendVoiceListenStart();
      print('$TAG: ✅ 语音通话录音完整启动成功！');
    } catch (e) {
      print('$TAG: ❌ 开始监听失败: $e');
      throw Exception('开始语音输入失败: $e');
    }
  }

  /// 停止听说（语音通话模式）
  Future<void> stopListeningCall() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送停止监听命令
      if (_sessionId != null && _messageManager != null) {
        await _messageManager!.sendVoiceListenStop();
      }
    } catch (e) {
      print('$TAG: 停止监听失败: $e');
    }
  }

  /// 取消发送（上滑取消）
  Future<void> abortListening() async {
    try {
      // 取消音频流订阅
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // 停止录音
      await AudioUtil.stopRecording();

      // 发送中止命令
      if (_sessionId != null && _messageManager != null) {
        await _messageManager!.sendUserInterrupt();
      }
    } catch (e) {
      print('$TAG: 中止监听失败: $e');
    }
  }

  /// 切换静音状态
  void toggleMute() {
    _isMuted = !_isMuted;

    if (_messageManager == null || !_isConnected) return;

    try {
      if (_isMuted) {
        _messageManager!.sendMute();
      } else {
        _messageManager!.sendUnmute();
      }
    } catch (e) {
      print('$TAG: 切换静音状态失败: $e');
    }
  }

  /// 中断音频播放
  Future<void> stopPlayback() async {
    try {
      print('$TAG: 正在停止音频播放');

      // 简单直接地停止播放
      await AudioUtil.stopPlaying();

      print('$TAG: 音频播放已停止');
    } catch (e) {
      print('$TAG: 停止音频播放失败: $e');
    }
  }

  /// 判断是否已连接
  bool get isConnected =>
      _isConnected &&
      _webSocketManager != null &&
      _webSocketManager!.isConnected;

  /// 判断是否静音
  bool get isMuted => _isMuted;

  /// 判断语音通话是否活跃
  bool get isVoiceCallActive => _stateCache.isVoiceCallActive;

  /// 释放资源
  Future<void> dispose() async {
    // 取消消息流订阅
    await _messageStreamSubscription?.cancel();
    _messageStreamSubscription = null;

    // 清理消息管理器
    _messageManager?.dispose();
    _messageManager = null;

    await disconnect();
    await AudioUtil.dispose();
    _listeners.clear();
    print('$TAG: 资源已释放');
  }

  /// 开始监听（按住说话模式）
  Future<void> startListening({String mode = 'manual'}) async {
    if (!_isConnected || _webSocketManager == null) {
      await connectVoiceCall();
    }

    try {
      // 确保已经有会话ID
      if (_sessionId == null) {
        print('$TAG: 没有会话ID，无法开始监听');
        return;
      }

      print('$TAG: 开始按住说话模式录音');

      // ⭐ 修复：设置按住说话模式标志
      _isPushToTalkMode = true;

      // ⭐ 修复：确保完全清理之前的状态
      await _cleanupPreviousRecording();

      // ⭐ 修复：先发送开始监听命令，再开始录音
      await _messageManager?.sendVoiceListenStart(
        mode: Mode.values.byName(mode),
      );
      print('$TAG: 已发送开始监听命令');

      // ⭐ 修复：等待更长时间确保服务器准备好接收音频
      await Future.delayed(const Duration(milliseconds: 200));

      // 开始录音
      await AudioUtil.startRecording();
      print('$TAG: 录音已开始');

      // ⭐ 修复：设置音频流订阅，确保只处理当前录音的数据
      int packetCount = 0;
      int sentPacketCount = 0; // ⭐ 新增：已发送包计数
      final currentRecordingId = DateTime.now().millisecondsSinceEpoch;
      print('$TAG: 当前录音ID: $currentRecordingId');

      _audioStreamSubscription = AudioUtil.audioStream.listen(
        (audioData) {
          // ⭐ 修复：检查是否仍在按住说话模式和录音状态
          if (!_isPushToTalkMode || !AudioUtil.isRecording) {
            print('$TAG: 不在按住说话模式或录音已停止，忽略音频数据');
            return;
          }

          packetCount++;
          if (packetCount % 20 == 1) {
            print(
              '$TAG: [录音$currentRecordingId] 发送音频包 #$packetCount，长度: ${audioData.length}',
            );
          }

          // ⭐ 改进：检查WebSocket连接状态再发送
          if (_webSocketManager != null && _isConnected) {
            _webSocketManager!.sendBinaryMessage(audioData);
            sentPacketCount++;
            if (sentPacketCount % 20 == 1) {
              print('$TAG: [录音$currentRecordingId] 已发送音频包 #$sentPacketCount');
            }
          } else {
            print('$TAG: ⚠️ WebSocket未连接，音频包 #$packetCount 发送失败');
          }
        },
        onError: (error) {
          print('$TAG: [录音$currentRecordingId] 音频流错误: $error');
        },
        onDone: () {
          print('$TAG: [录音$currentRecordingId] 音频流结束，共发送 $packetCount 个包');
        },
      );

      print('$TAG: 按住说话录音启动完成，录音ID: $currentRecordingId');
    } catch (e) {
      print('$TAG: 开始监听失败: $e');
      // 出错时清理资源
      await _cleanupPreviousRecording();
      _isPushToTalkMode = false;
      throw Exception('开始语音输入失败: $e');
    }
  }

  /// 停止监听（按住说话模式）
  Future<void> stopListening() async {
    try {
      print('$TAG: 按住说话结束，开始停止流程');

      // ⭐ 修复：先停止录音，确保不再产生新的音频数据
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
        print('$TAG: 已停止录音');
      }

      // ⭐ 修复：等待更长时间，确保最后的音频数据发送完成
      // 考虑到网络延迟和缓冲，增加等待时间到500ms
      await Future.delayed(const Duration(milliseconds: 500));

      // ⭐ 修复：发送停止监听命令，告诉服务器处理已收到的音频
      if (_sessionId != null && _messageManager != null) {
        await _messageManager!.sendVoiceListenStop();
        print('$TAG: 已发送停止监听命令，服务器开始处理音频');
      }

      // ⭐ 修复：再等待一小段时间确保停止命令发送完成
      await Future.delayed(const Duration(milliseconds: 100));

      // ⭐ 修复：最后取消音频流订阅，停止发送音频数据
      if (_audioStreamSubscription != null) {
        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = null;
        print('$TAG: 已取消音频流订阅');
      }

      // ⭐ 修复：最后设置标志，确保所有音频数据都已处理
      _isPushToTalkMode = false;

      print('$TAG: 按住说话停止完成，等待服务器响应');
    } catch (e) {
      print('$TAG: 停止监听失败: $e');
      // 出错时确保清理资源
      await _cleanupPreviousRecording();
    }
  }

  /// ⭐ 新增：清理之前录音的辅助方法
  Future<void> _cleanupPreviousRecording() async {
    try {
      // 取消音频流订阅
      if (_audioStreamSubscription != null) {
        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = null;
        print('$TAG: 已清理音频流订阅');
      }

      // 停止录音
      if (AudioUtil.isRecording) {
        await AudioUtil.stopRecording();
        print('$TAG: 已停止之前的录音');
      }

      // 等待一小段时间确保清理完成
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      print('$TAG: 清理之前录音失败: $e');
    }
  }

  /// 发送中断消息
  Future<void> sendAbortMessage() async {
    try {
      if (_messageManager != null && _isConnected && _sessionId != null) {
        await _messageManager!.sendUserInterrupt();

        // 停止当前播放
        await stopPlayback();

        // 如果当前正在录音，暂停录音一段时间后自动重新开始
        if (_isSpeaking && _stateCache.isVoiceCallActive) {
          await stopListeningCall();
          print('$TAG: 已停止录音，等待重新开始...');

          // 延迟后自动重新开始录音（模拟语音通话的连续性）
          await Future.delayed(const Duration(milliseconds: 1000));

          if (_stateCache.isVoiceCallActive) {
            await startListeningCall();
            print('$TAG: 已重新开始录音');
          }
        }
      }
    } catch (e) {
      print('$TAG: 发送中断消息失败: $e');
      rethrow;
    }
  }

  /// 判断是否正在说话
  bool get _isSpeaking => _audioStreamSubscription != null;

  /// 判断是否处于按住说话模式
  bool get isPushToTalkMode => _isPushToTalkMode;
}
