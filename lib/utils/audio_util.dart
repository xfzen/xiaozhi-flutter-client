import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter_pcm_player/flutter_pcm_player.dart';

/// 音频工具类，用于处理Opus音频编解码和录制播放
class AudioUtil {
  static const String TAG = "AudioUtil";
  static const int SAMPLE_RATE = 16000;
  static const int CHANNELS = 1;
  static const int FRAME_DURATION = 60; // 毫秒

  static final AudioRecorder _audioRecorder = AudioRecorder();
  static ja.AudioPlayer? _player;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  static String? _tempFilePath;
  static Timer? _audioProcessingTimer;

  // Opus相关
  static SimpleOpusEncoder? _encoder;
  static SimpleOpusDecoder? _decoder;
  static bool _opusAvailable = false;

  /// 初始化Opus编解码器
  static void _initOpusCodecs() {
    if (_opusAvailable) return; // 已经初始化过了

    // 在macOS上，我们不使用Opus编码，直接使用PCM
    if (Platform.isMacOS) {
      print('$TAG: macOS平台使用PCM格式，跳过Opus初始化');
      _encoder = null;
      _decoder = null;
      _opusAvailable = false;
      return;
    }

    try {
      // 其他平台使用Opus
      _encoder = SimpleOpusEncoder(
        sampleRate: SAMPLE_RATE,
        channels: CHANNELS,
        application: Application.voip,
      );
      _decoder = SimpleOpusDecoder(sampleRate: SAMPLE_RATE, channels: CHANNELS);
      _opusAvailable = true;
      print('$TAG: Opus编解码器初始化成功');
    } catch (e) {
      print('$TAG: Opus编解码器初始化失败: $e');
      _encoder = null;
      _decoder = null;
      _opusAvailable = false;
    }
  }

  // FlutterPcmPlayer实例（仅非macOS平台使用）
  static FlutterPcmPlayer? _pcmPlayer;

  // macOS音频播放相关
  static ja.AudioPlayer? _macAudioPlayer;
  static StreamController<List<int>>? _macAudioController;
  static String? _tempAudioFile;

  /// 获取音频流
  static Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 初始化音频录制器
  static Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;

    print('$TAG: 开始初始化录音器');

    // 更积极地请求所有可能需要的权限（仅在移动平台）
    if (Platform.isAndroid) {
      print('$TAG: 请求Android所需的所有权限');
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.microphone,
            Permission.storage,
            Permission.manageExternalStorage,
            Permission.bluetooth,
            Permission.bluetoothConnect,
            Permission.bluetoothScan,
          ].request();

      print('$TAG: 权限状态:');
      statuses.forEach((permission, status) {
        print('$TAG: $permission: $status');
      });

      if (statuses[Permission.microphone] != PermissionStatus.granted) {
        print('$TAG: 麦克风权限被拒绝');
        throw Exception('需要麦克风权限');
      }
    } else if (Platform.isIOS) {
      // iOS只请求麦克风权限
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('$TAG: 麦克风权限被拒绝');
        throw Exception('需要麦克风权限');
      }
    } else {
      // 桌面平台跳过权限检查
      print('$TAG: 桌面平台跳过权限检查');
    }

    // 检查是否可用
    print('$TAG: 检查PCM16编码是否支持');
    final isAvailable = await _audioRecorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    print('$TAG: PCM16编码支持状态: $isAvailable');

    // 设置音频模式 - 参考Android原生实现
    print('$TAG: 配置音频会话');
    final session = await AudioSession.instance;

    // 使用与原生Android实现更接近的配置
    if (Platform.isAndroid) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientExclusive,
          androidWillPauseWhenDucked: false,
        ),
      );
    } else {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
        ),
      );
      await session.setActive(true);
    }

    // 初始化Opus编解码器
    _initOpusCodecs();

    _isRecorderInitialized = true;
    print('$TAG: 录音器初始化成功');
  }

  /// 初始化音频播放器
  static Future<void> initPlayer() async {
    // 确保任何旧播放器被释放
    await stopPlaying();

    try {
      if (Platform.isMacOS) {
        print('$TAG: macOS平台使用just_audio播放器');
        _macAudioPlayer = ja.AudioPlayer();
        _isPlayerInitialized = true;
        print('$TAG: macOS音频播放器初始化成功');
      } else {
        print('$TAG: 使用简单方式初始化PCM播放器');
        // 创建新的播放器实例 - 完全按照官方示例的简单方式
        _pcmPlayer = FlutterPcmPlayer();
        await _pcmPlayer!.initialize();
        await _pcmPlayer!.play();
        _isPlayerInitialized = true;
        print('$TAG: PCM播放器初始化成功');
      }
    } catch (e) {
      print('$TAG: 播放器初始化失败: $e');
      _isPlayerInitialized = false;
    }
  }

  /// 播放PCM音频数据
  static Future<void> playPcmData(Uint8List pcmData) async {
    try {
      // 如果播放器未初始化，先初始化
      if (!_isPlayerInitialized) {
        await initPlayer();
      }

      if (Platform.isMacOS) {
        // 在macOS上使用just_audio播放PCM数据
        await _playPcmOnMacOS(pcmData);
      } else {
        // 在其他平台使用PCM播放器
        if (_pcmPlayer != null) {
          await _pcmPlayer!.feed(pcmData);
        }
      }
    } catch (e) {
      print('$TAG: PCM数据播放失败: $e');
      await stopPlaying();
      await initPlayer();
    }
  }

  /// 播放Opus音频数据
  static Future<void> playOpusData(Uint8List opusData) async {
    try {
      // 如果播放器未初始化，先初始化
      if (!_isPlayerInitialized) {
        await initPlayer();
      }

      if (Platform.isMacOS) {
        await _playOpusOnMacOS(opusData);
      } else {
        await _playOpusOnMobile(opusData);
      }
    } catch (e) {
      print('$TAG: 播放失败: $e');

      // 简单重置并重新初始化
      await stopPlaying();
      await initPlayer();
    }
  }

  /// 在移动平台播放Opus数据
  static Future<void> _playOpusOnMobile(Uint8List opusData) async {
    // 确保Opus解码器已初始化
    if (!_opusAvailable || _decoder == null) {
      _initOpusCodecs();
    }

    if (!_opusAvailable || _decoder == null) {
      print('$TAG: Opus解码器不可用，跳过播放');
      return;
    }

    // 解码Opus数据
    final Int16List pcmData = _decoder!.decode(input: opusData);

    // 准备PCM数据（按照示例直接方式）
    final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
    ByteData bytes = ByteData.view(pcmBytes.buffer);

    // 使用小端字节序
    for (int i = 0; i < pcmData.length; i++) {
      bytes.setInt16(i * 2, pcmData[i], Endian.little);
    }

    // 直接发送到播放器
    if (_pcmPlayer != null) {
      await _pcmPlayer!.feed(pcmBytes);
    }
  }

  /// 在macOS上播放PCM数据
  static Future<void> _playPcmOnMacOS(Uint8List pcmData) async {
    try {
      if (_macAudioPlayer == null) {
        print('$TAG: macOS音频播放器为null');
        return;
      }

      // 创建临时WAV文件
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _tempAudioFile = '${tempDir.path}/temp_audio_$timestamp.wav';

      // 将PCM数据转换为WAV格式
      final wavData = _createWavFile(pcmData);
      await File(_tempAudioFile!).writeAsBytes(wavData);

      // 播放文件
      await _macAudioPlayer!.setFilePath(_tempAudioFile!);
      await _macAudioPlayer!.play();
      _isPlaying = true;

      print('$TAG: macOS PCM音频播放开始，文件: $_tempAudioFile');
    } catch (e) {
      print('$TAG: macOS PCM音频播放失败: $e');
    }
  }

  /// 在macOS上播放Opus数据
  static Future<void> _playOpusOnMacOS(Uint8List opusData) async {
    try {
      if (_macAudioPlayer == null) {
        print('$TAG: macOS音频播放器为null');
        return;
      }

      Uint8List pcmData;

      // 尝试解码Opus数据
      if (_opusAvailable && _decoder != null) {
        try {
          final Int16List decodedData = _decoder!.decode(input: opusData);
          // 转换为字节数组
          final Uint8List pcmBytes = Uint8List(decodedData.length * 2);
          ByteData bytes = ByteData.view(pcmBytes.buffer);
          for (int i = 0; i < decodedData.length; i++) {
            bytes.setInt16(i * 2, decodedData[i], Endian.little);
          }
          pcmData = pcmBytes;
        } catch (e) {
          print('$TAG: Opus解码失败，直接使用原始数据: $e');
          pcmData = opusData;
        }
      } else {
        print('$TAG: Opus解码器不可用，直接使用原始数据');
        pcmData = opusData;
      }

      // 创建临时WAV文件
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _tempAudioFile = '${tempDir.path}/temp_audio_$timestamp.wav';

      // 将PCM数据转换为WAV格式
      final wavData = _createWavFile(pcmData);
      await File(_tempAudioFile!).writeAsBytes(wavData);

      // 播放文件
      await _macAudioPlayer!.setFilePath(_tempAudioFile!);
      await _macAudioPlayer!.play();
      _isPlaying = true;

      print('$TAG: macOS音频播放开始，文件: $_tempAudioFile');
    } catch (e) {
      print('$TAG: macOS音频播放失败: $e');
    }
  }

  /// 创建WAV文件头
  static Uint8List _createWavFile(Uint8List pcmData) {
    const int sampleRate = SAMPLE_RATE;
    const int channels = CHANNELS;
    const int bitsPerSample = 16;

    final int dataSize = pcmData.length;
    final int fileSize = 44 + dataSize;

    final List<int> header = [
      // RIFF header
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      ...intToBytes(fileSize - 8, 4), // File size - 8
      0x57, 0x41, 0x56, 0x45, // "WAVE"
      // fmt chunk
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      0x10, 0x00, 0x00, 0x00, // Chunk size (16)
      0x01, 0x00, // Audio format (PCM)
      ...intToBytes(channels, 2), // Number of channels
      ...intToBytes(sampleRate, 4), // Sample rate
      ...intToBytes(
        sampleRate * channels * (bitsPerSample ~/ 8),
        4,
      ), // Byte rate
      ...intToBytes(channels * (bitsPerSample ~/ 8), 2), // Block align
      ...intToBytes(bitsPerSample, 2), // Bits per sample
      // data chunk
      0x64, 0x61, 0x74, 0x61, // "data"
      ...intToBytes(dataSize, 4), // Data size
    ];

    return Uint8List.fromList([...header, ...pcmData]);
  }

  /// 将整数转换为字节数组（小端序）
  static List<int> intToBytes(int value, int bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes; i++) {
      result.add((value >> (i * 8)) & 0xFF);
    }
    return result;
  }

  /// 停止播放
  static Future<void> stopPlaying() async {
    _isPlaying = false;

    if (Platform.isMacOS) {
      // macOS平台停止播放
      if (_macAudioPlayer != null) {
        try {
          await _macAudioPlayer!.stop();
          print('$TAG: macOS播放器已停止');
        } catch (e) {
          print('$TAG: 停止macOS播放失败: $e');
        }
      }

      // 清理临时文件
      if (_tempAudioFile != null) {
        try {
          final file = File(_tempAudioFile!);
          if (await file.exists()) {
            await file.delete();
            print('$TAG: 临时音频文件已删除: $_tempAudioFile');
          }
        } catch (e) {
          print('$TAG: 删除临时文件失败: $e');
        }
        _tempAudioFile = null;
      }
    } else {
      // 移动平台停止播放
      if (_pcmPlayer != null) {
        try {
          await _pcmPlayer!.stop();
          print('$TAG: PCM播放器已停止');
        } catch (e) {
          print('$TAG: 停止PCM播放失败: $e');
        }
        _pcmPlayer = null;
        _isPlayerInitialized = false;
      }
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await stopPlaying();

    if (Platform.isMacOS) {
      _macAudioPlayer?.dispose();
      _macAudioPlayer = null;
      _macAudioController?.close();
      _macAudioController = null;
    }

    _audioStreamController.close();
    print('$TAG: 资源已释放');
  }

  /// 开始录音
  static Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    if (_isRecording) return;

    try {
      print('$TAG: 尝试启动录音');

      // 确保麦克风权限已获取（仅在移动平台） - 使用不同方式检查权限
      if (Platform.isIOS || Platform.isAndroid) {
        final status = await Permission.microphone.status;
        print('$TAG: 麦克风权限状态: $status');

        if (status != PermissionStatus.granted) {
          final result = await Permission.microphone.request();
          print('$TAG: 请求麦克风权限结果: $result');
          if (result != PermissionStatus.granted) {
            print('$TAG: 麦克风权限被拒绝');
            return;
          }
        }
      } else {
        print('$TAG: 桌面平台跳过权限检查');
      }

      // 尝试直接使用音频流
      try {
        print('$TAG: 尝试启动流式录音');
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: SAMPLE_RATE,
            numChannels: CHANNELS,
          ),
        );

        _isRecording = true;
        print('$TAG: 流式录音启动成功');

        // 直接从流中处理数据
        stream.listen(
          (data) async {
            if (data.isNotEmpty && data.length % 2 == 0) {
              if (Platform.isMacOS) {
                // macOS上直接发送PCM数据
                _audioStreamController.add(data);
              } else {
                // 其他平台使用Opus编码
                final opusData = await encodeToOpus(data);
                if (opusData != null) {
                  _audioStreamController.add(opusData);
                }
              }
            }
          },
          onError: (error) {
            print('$TAG: 音频流错误: $error');
            _isRecording = false;
          },
          onDone: () {
            print('$TAG: 音频流结束');
            _isRecording = false;
          },
        );
      } catch (e) {
        print('$TAG: 流式录音失败: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      print('$TAG: 启动录音失败: $e');
      print(stackTrace);
      _isRecording = false;
    }
  }

  /// 停止录音
  static Future<String?> stopRecording() async {
    if (!_isRecorderInitialized || !_isRecording) return null;

    // 取消定时器
    _audioProcessingTimer?.cancel();

    // 停止录音
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      print('$TAG: 停止录音: $path');
      return path;
    } catch (e) {
      print('$TAG: 停止录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  /// 将PCM数据编码为Opus格式
  static Future<Uint8List?> encodeToOpus(Uint8List pcmData) async {
    try {
      // 确保Opus编码器已初始化
      if (_encoder == null) {
        _initOpusCodecs();
      }

      if (_encoder == null) {
        print('$TAG: Opus编码器不可用，返回null');
        return null;
      }

      // 删除频繁日志
      // 转换PCM数据为Int16List (小端字节序，与Android一致)
      final Int16List pcmInt16 = Int16List.fromList(
        List.generate(
          pcmData.length ~/ 2,
          (i) => (pcmData[i * 2]) | (pcmData[i * 2 + 1] << 8),
        ),
      );

      // 确保数据长度符合Opus要求（必须是2.5ms、5ms、10ms、20ms、40ms或60ms的采样数）
      final int samplesPerFrame = (SAMPLE_RATE * FRAME_DURATION) ~/ 1000;

      Uint8List encoded;

      // 处理过短的数据
      if (pcmInt16.length < samplesPerFrame) {
        // 对于过短的数据，可以通过添加静音来填充到所需长度
        final Int16List paddedData = Int16List(samplesPerFrame);
        for (int i = 0; i < pcmInt16.length; i++) {
          paddedData[i] = pcmInt16[i];
        }

        // 编码填充后的数据
        encoded = Uint8List.fromList(_encoder!.encode(input: paddedData));
      } else {
        // 对于足够长的数据，裁剪到精确的帧长度
        encoded = Uint8List.fromList(
          _encoder!.encode(input: pcmInt16.sublist(0, samplesPerFrame)),
        );
      }

      return encoded;
    } catch (e, stackTrace) {
      print('$TAG: Opus编码失败: $e');
      print(stackTrace);
      return null;
    }
  }

  /// 检查是否正在录音
  static bool get isRecording => _isRecording;

  /// 检查是否正在播放
  static bool get isPlaying => _isPlaying;
}
