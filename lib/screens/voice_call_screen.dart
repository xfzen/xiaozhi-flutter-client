import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/utils/audio_util.dart';
import 'dart:async';
import 'dart:io';

class VoiceCallScreen extends StatefulWidget {
  final Conversation conversation;
  final XiaozhiConfig xiaozhiConfig;

  const VoiceCallScreen({
    super.key,
    required this.conversation,
    required this.xiaozhiConfig,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late XiaozhiService _xiaozhiService;
  bool _isConnected = false;
  bool _isSpeaking = false;
  String _statusText = '正在连接...';
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;
  bool _serverReady = false;
  Timer? _statusUpdateTimer; // 添加状态更新定时器

  late AnimationController _animationController;
  final List<double> _audioLevels = List.filled(30, 0.05);
  Timer? _audioVisualizerTimer;

  // 添加状态管理变量
  bool _isInitializing = false;
  bool _hasAutoStarted = false; // 防止重复自动开始录音
  DateTime? _lastDetailedReport; // 用于控制详细报告输出频率

  @override
  void initState() {
    super.initState();

    // 设置状态栏为透明并使图标为白色
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    // 在帧绘制后再次设置系统UI样式，避免被覆盖
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      );
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // 获取XiaozhiService实例
    print('VoiceCallScreen: 初始化小智服务');
    print('  对话ID: ${widget.conversation.id}');
    print('  配置名称: ${widget.xiaozhiConfig.name}');
    print('  WebSocket URL: ${widget.xiaozhiConfig.websocketUrl}');
    print('  MAC地址: ${widget.xiaozhiConfig.macAddress}');
    print('  Token: ${widget.xiaozhiConfig.token}');

    _xiaozhiService = XiaozhiService(
      websocketUrl: widget.xiaozhiConfig.websocketUrl,
      macAddress: widget.xiaozhiConfig.macAddress,
      token: widget.xiaozhiConfig.token,
      sessionId: widget.conversation.id,
    );

    // 设置消息监听器
    _xiaozhiService.setMessageListener(_handleServerMessage);

    // 连接并切换到语音通话模式
    _connectToVoiceService();
    _startAudioVisualizer();
    _startStatusUpdateTimer(); // 启动状态更新定时器
  }

  void _handleServerMessage(dynamic message) {
    // 检查页面是否还在，如果已经销毁则不处理
    if (!mounted) {
      print('页面已销毁，忽略消息: $message');
      return;
    }

    // 处理服务器发来的消息
    if (message is Map<String, dynamic> && message['type'] == 'hello') {
      print('VoiceCallScreen: 🤝 服务器准备就绪');

      // 使用mounted检查后再调用setState
      if (mounted) {
        setState(() {
          _serverReady = true;
        });
      }

      // ⭐ 修复：确保在服务器hello后自动开始录音
      if (!_hasAutoStarted && _isConnected && mounted) {
        _hasAutoStarted = true; // 防止重复自动开始
        print('VoiceCallScreen: 🎙️ 服务器hello已收到，自动开始录音...');

        // 延迟一小段时间确保所有初始化完成
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (mounted && _serverReady && !_isInitializing) {
            try {
              _startSpeaking();
              print('VoiceCallScreen: ✅ 自动录音启动成功');
            } catch (e) {
              print('VoiceCallScreen: ❌ 自动录音启动失败: $e');
              // 如果自动启动失败，重置标志，允许手动重试
              _hasAutoStarted = false;
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    print('VoiceCallScreen: 开始销毁页面');

    // 立即清理消息监听器，防止继续接收消息
    _xiaozhiService.setMessageListener(null);

    // 先停止所有定时器
    _callTimer?.cancel();
    _audioVisualizerTimer?.cancel();
    _statusUpdateTimer?.cancel(); // 停止状态更新定时器
    _animationController.dispose();

    // 确保停止录音和播放
    _xiaozhiService.stopPlayback();

    // 异步清理资源，避免阻塞UI
    Future.microtask(() async {
      try {
        // 停止语音通话
        if (_isSpeaking) {
          await _xiaozhiService.stopListeningCall();
        }

        // 切换回普通聊天模式
        await _xiaozhiService.switchToChatMode();

        print('VoiceCallScreen: 资源清理完成');
      } catch (e) {
        print('VoiceCallScreen: 资源清理时发生错误: $e');
      }
    });

    super.dispose();
    print('VoiceCallScreen: 页面销毁完成');
  }

  void _connectToVoiceService() async {
    if (_isInitializing || !mounted) return; // 防止重复初始化

    if (mounted) {
      setState(() {
        _isInitializing = true;
        _statusText = '正在准备...';
      });
    }

    try {
      // 显示连接进度
      if (mounted) {
        setState(() {
          _statusText = '正在连接服务器...';
        });
      }

      // 切换到语音通话模式
      await _xiaozhiService.switchToVoiceCallMode();

      // 等待一小段时间确保连接完全建立
      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted) {
        setState(() {
          _statusText = '已连接';
          _isConnected = true;
          _isInitializing = false;
        });

        // 显示连接成功的提示
        _showCustomSnackbar(
          message: '已进入语音通话模式',
          icon: Icons.check_circle,
          iconColor: Colors.greenAccent,
        );

        _startCallTimer();

        // 添加会话消息
        Provider.of<ConversationProvider>(context, listen: false).addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: '语音通话已开始',
        );
      }

      // 不要在这里立即开始录音，等待服务器hello消息后再开始
      // 这样可以避免重复开始录音的问题
      print('连接成功，等待服务器hello消息...');
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '连接失败';
          _isConnected = false;
          _isInitializing = false;
        });

        print('准备失败: $e');

        String errorMessage = e.toString();
        if (errorMessage.contains('权限')) {
          errorMessage = '麦克风权限被拒绝，请检查应用权限设置';
        } else if (errorMessage.contains('连接')) {
          errorMessage = '网络连接失败，请检查网络设置';
        }

        _showCustomSnackbar(
          message: errorMessage,
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = Duration(seconds: timer.tick);
        });
      } else {
        // 如果页面已销毁，取消定时器
        timer.cancel();
      }
    });
  }

  void _startAudioVisualizer() {
    _audioVisualizerTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (mounted && _isConnected) {
        setState(() {
          // Simulate audio levels
          for (int i = 0; i < _audioLevels.length - 1; i++) {
            _audioLevels[i] = _audioLevels[i + 1];
          }

          if (_isSpeaking) {
            _audioLevels[_audioLevels.length - 1] =
                0.05 + (0.6 * (0.5 + 0.5 * _animationController.value));
          } else {
            _audioLevels[_audioLevels.length - 1] =
                0.05 + (0.1 * (0.5 + 0.5 * _animationController.value));
          }
        });
      } else if (!mounted) {
        // 如果页面已销毁，取消定时器
        timer.cancel();
      }
    });
  }

  // 开始录音
  void _startSpeaking() async {
    if (_isSpeaking || _isInitializing || !mounted) {
      print(
        'VoiceCallScreen: ⚠️ 录音状态检查失败 - 正在录音:$_isSpeaking, 初始化中:$_isInitializing, 页面已销毁:${!mounted}',
      );
      return; // 防止重复操作
    }

    print('VoiceCallScreen: 🎤 开始录音流程...');

    if (mounted) {
      setState(() {
        _isSpeaking = true;
      });
    }

    try {
      // ⭐ 修复：确保WebSocket连接状态正常
      if (!_xiaozhiService.isConnected) {
        print('VoiceCallScreen: ⚠️ WebSocket未连接，无法开始录音');
        throw Exception('WebSocket连接未建立');
      }

      // 开始录音并订阅音频流
      print('VoiceCallScreen: 📞 调用XiaozhiService.startListeningCall()...');
      await _xiaozhiService.startListeningCall();

      if (mounted) {
        _showCustomSnackbar(
          message: '正在录音中...',
          icon: Icons.mic,
          iconColor: Colors.greenAccent,
        );
        print('VoiceCallScreen: ✅ 录音启动成功');
      }
    } catch (e) {
      print('VoiceCallScreen: ❌ 开始录音失败: $e');
      // 如果失败，恢复状态
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });

        _showCustomSnackbar(
          message: '开始录音失败: $e',
          icon: Icons.error,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  // 发送打断消息
  void _sendAbortMessage() async {
    try {
      // 发送打断消息
      await _xiaozhiService.sendAbortMessage();

      if (mounted) {
        _showCustomSnackbar(
          message: '已发送打断信号',
          icon: Icons.pan_tool,
          iconColor: Colors.orangeAccent,
        );
      }
    } catch (e) {
      print('发送打断信号失败: $e');
      if (mounted) {
        _showCustomSnackbar(
          message: '发送打断信号失败: $e',
          icon: Icons.error,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // 获取状态颜色
  Color _getStatusColor() {
    if (_isInitializing) {
      return Colors.orange;
    } else if (_isConnected) {
      // 检查XiaozhiService的真实录音状态
      bool isReallyRecording =
          _xiaozhiService.isConnected && _xiaozhiService.isVoiceCallActive;
      return isReallyRecording ? Colors.blue : Colors.green;
    } else {
      return Colors.red;
    }
  }

  // 获取状态图标
  IconData _getStatusIcon() {
    if (_isInitializing) {
      return Icons.hourglass_empty;
    } else if (_isConnected) {
      // 检查XiaozhiService的真实录音状态
      bool isReallyRecording =
          _xiaozhiService.isConnected && _xiaozhiService.isVoiceCallActive;
      return isReallyRecording ? Icons.mic : Icons.check_circle;
    } else {
      return Icons.error_outline;
    }
  }

  // 获取状态文本
  String _getStatusText() {
    if (_isInitializing) {
      return '正在初始化...';
    } else if (_isConnected) {
      // 检查XiaozhiService的真实录音状态
      bool isReallyRecording =
          _xiaozhiService.isConnected && _xiaozhiService.isVoiceCallActive;

      if (isReallyRecording && _serverReady) {
        return '$_statusText (正在录音)';
      } else if (_serverReady) {
        return '$_statusText (准备就绪)';
      } else {
        return '$_statusText (等待服务器)';
      }
    } else {
      return _statusText;
    }
  }

  void _startStatusUpdateTimer() {
    _statusUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (mounted) {
        // 定期更新状态显示，确保反映XiaozhiService的最新状态
        setState(() {
          // 状态更新会触发_getStatusText()等方法重新计算
        });

        // 每5秒打印一次详细的录音状态报告
        if (timer.tick % 10 == 0) {
          // 500ms * 10 = 5秒
          _printRecordingStatusReport();
        }
      } else {
        // 如果页面已销毁，取消定时器
        timer.cancel();
      }
    });
  }

  void _printRecordingStatusReport() {
    // ⭐ 合并日志：只在状态变化或每30秒输出一次详细报告
    final now = DateTime.now();

    bool shouldPrintDetailed =
        _lastDetailedReport == null ||
        now.difference(_lastDetailedReport!).inSeconds > 30;

    if (shouldPrintDetailed) {
      print('=== 🎙️ 录音状态报告 ===');
      print('VoiceCallScreen状态:');
      print('  - 页面mounted: $mounted');
      print('  - 本地连接状态: $_isConnected');
      print('  - 服务器就绪: $_serverReady');
      print('  - 初始化状态: $_isInitializing');

      print('XiaozhiService状态:');
      print('  - 服务连接状态: ${_xiaozhiService.isConnected}');
      print('  - 语音通话活跃: ${_xiaozhiService.isVoiceCallActive}');

      print('AudioUtil状态:');
      print('  - 正在录音: ${AudioUtil.isRecording}');
      print('================');

      _lastDetailedReport = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 确保状态栏设置正确
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: Container(
          margin: const EdgeInsets.only(left: 8, top: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            onPressed: () {
              // 返回前停止播放
              _xiaozhiService.stopPlayback();
              Navigator.pop(context);
            },
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 渐变背景
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  Theme.of(context).colorScheme.primary.withOpacity(0.6),
                ],
              ),
            ),
          ),

          // 水波纹背景
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [Colors.white.withOpacity(0.1), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // 主要内容
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 圆形头像
                Hero(
                  tag: 'avatar_${widget.conversation.id}',
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.9),
                          Theme.of(context).colorScheme.primaryContainer,
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 名称显示
                Text(
                  widget.conversation.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 状态显示 - 使用拟物化样式
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor().withOpacity(0.6),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor().withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(),
                        color: _getStatusColor(),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          color: _getStatusColor(),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 通话时长
                Text(
                  '通话时长: ${_formatDuration(_callDuration)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 40),

                // 音频可视化
                _buildAudioVisualizer(),
                const SizedBox(height: 60),

                // 通话控制按钮
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildEndCallButton(),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: Icons.pan_tool, // 改为手掌图标表示打断
                        color: Colors.white,
                        backgroundColor: Colors.orange,
                        onPressed: _sendAbortMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioVisualizer() {
    return Container(
      width: 240,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _audioLevels.length,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            curve: Curves.easeInOut,
            width: 4,
            height: 80 * _audioLevels[index],
            decoration: BoxDecoration(
              color: _getBarColor(index, _audioLevels[index]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBarColor(int index, double level) {
    if (_isSpeaking) {
      // 渐变从蓝色到绿色
      double position = index / _audioLevels.length;
      return Color.lerp(
        Colors.blue.shade400,
        Colors.green.shade400,
        position,
      )!.withOpacity(0.7 + 0.3 * level);
    } else {
      // 非说话状态时使用柔和的蓝色
      return Colors.blue.shade200.withOpacity(0.3 + 0.4 * level);
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    double size = 56,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: backgroundColor.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(child: Icon(icon, color: color, size: size * 0.45)),
        ),
      ),
    );
  }

  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: () async {
        // 先发送打断消息
        await _xiaozhiService.sendAbortMessage();
        // 然后返回上一级页面
        Navigator.pop(context);
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.red.shade400.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  // 显示自定义Snackbar
  void _showCustomSnackbar({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    // 确保页面仍然mounted并且有正确的context
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final snackBar = SnackBar(
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
      );

      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      print('VoiceCallScreen: 显示SnackBar时出错: $e');
    }
  }
}
