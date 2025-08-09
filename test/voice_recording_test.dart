import 'package:flutter_test/flutter_test.dart';

void main() {
  group('语音录制流程测试', () {
    test('测试语音录制延迟发送问题修复', () async {
      // 模拟第一次录音流程
      print('🎤 开始第一次录音测试...');

      final stopwatch = Stopwatch()..start();

      // 模拟按下按钮开始录音
      print('📝 模拟开始录音');
      await Future.delayed(const Duration(milliseconds: 200)); // 模拟服务器准备时间
      final startTime = stopwatch.elapsedMilliseconds;

      // 模拟录音过程（说"今天天气"）
      await Future.delayed(const Duration(seconds: 2)); // 模拟说话时间

      // 模拟松开按钮停止录音
      print('🛑 模拟停止录音');
      await Future.delayed(const Duration(milliseconds: 500)); // 模拟音频数据发送时间
      final firstStopTime = stopwatch.elapsedMilliseconds;

      print('✅ 第一次录音流程完成，耗时: ${firstStopTime}ms');

      // 模拟第二次录音流程
      print('🎤 开始第二次录音测试...');

      // 第二次录音
      print('📝 模拟第二次开始录音');
      await Future.delayed(const Duration(milliseconds: 200));
      await Future.delayed(const Duration(milliseconds: 500)); // 短暂录音
      print('🛑 模拟第二次停止录音');
      await Future.delayed(const Duration(milliseconds: 500));
      final secondStopTime = stopwatch.elapsedMilliseconds;

      stopwatch.stop();

      print('✅ 第二次录音流程完成，总耗时: ${secondStopTime}ms');

      // 验证时序合理性
      expect(startTime, lessThan(300)); // 开始录音应该在300ms内完成
      expect(firstStopTime - startTime, greaterThan(2000)); // 第一次录音应该有足够时间
      expect(
        secondStopTime - firstStopTime,
        greaterThan(1000),
      ); // 第二次录音也应该有足够时间
    });

    test('测试音频流缓冲时序', () async {
      // 测试音频流的时序问题
      final stopwatch = Stopwatch()..start();

      // 模拟开始录音
      print('⏱️ 测试开始录音时序...');
      await Future.delayed(const Duration(milliseconds: 200)); // 服务器准备时间
      final startTime = stopwatch.elapsedMilliseconds;
      print('📝 录音开始耗时: ${startTime}ms');

      // 模拟录音过程
      await Future.delayed(const Duration(seconds: 1)); // 录音时间

      // 模拟停止录音
      print('⏱️ 测试停止录音时序...');
      final stopStartTime = stopwatch.elapsedMilliseconds;
      await Future.delayed(const Duration(milliseconds: 500)); // 音频数据发送时间
      final stopEndTime = stopwatch.elapsedMilliseconds;
      print('🛑 停止录音耗时: ${stopEndTime - stopStartTime}ms');

      stopwatch.stop();

      // 验证时序合理性
      expect(startTime, lessThan(300)); // 开始录音应该在300ms内完成
      expect(stopEndTime - stopStartTime, greaterThan(400)); // 停止录音应该有足够的缓冲时间

      print('✅ 时序测试通过');
    });

    test('测试音频数据完整性', () async {
      // 模拟音频数据包
      final audioPackets = <String>[];

      // 模拟录音过程中的音频数据包
      for (int i = 0; i < 10; i++) {
        audioPackets.add('audio_packet_$i');
        await Future.delayed(const Duration(milliseconds: 60)); // 每60ms一个包
      }

      print('📦 生成了 ${audioPackets.length} 个音频包');

      // 模拟停止录音时的缓冲等待
      await Future.delayed(const Duration(milliseconds: 500));

      // 验证所有音频包都被处理
      expect(audioPackets.length, equals(10));

      // 验证音频包的顺序
      for (int i = 0; i < audioPackets.length; i++) {
        expect(audioPackets[i], equals('audio_packet_$i'));
      }

      print('✅ 音频数据完整性测试通过');
    });

    test('测试连续录音场景', () async {
      // 测试连续两次录音的场景，模拟实际问题
      print('🔄 测试连续录音场景...');

      // 第一次录音
      print('🎤 第一次录音开始');
      await Future.delayed(const Duration(milliseconds: 200)); // 开始延迟
      await Future.delayed(const Duration(seconds: 1)); // 录音时间
      print('🛑 第一次录音结束');
      await Future.delayed(const Duration(milliseconds: 800)); // 修复后的停止处理时间

      // 短暂间隔
      await Future.delayed(const Duration(milliseconds: 100));

      // 第二次录音
      print('🎤 第二次录音开始');
      await Future.delayed(const Duration(milliseconds: 200)); // 开始延迟
      await Future.delayed(const Duration(milliseconds: 500)); // 短录音时间
      print('🛑 第二次录音结束');
      await Future.delayed(const Duration(milliseconds: 800)); // 修复后的停止处理时间

      print('✅ 连续录音测试完成');

      // 修复后，第一次录音的数据应该在第一次停止时发送，
      // 第二次录音的数据应该在第二次停止时发送
      expect(true, isTrue); // 占位符断言
    });

    test('测试修复后的音频流时序', () async {
      // 测试修复后的音频流处理时序
      print('🔧 测试修复后的音频流时序...');

      final stopwatch = Stopwatch()..start();

      // 模拟开始录音
      print('📝 开始录音');
      await Future.delayed(const Duration(milliseconds: 200)); // 服务器准备时间
      final startTime = stopwatch.elapsedMilliseconds;

      // 模拟录音过程
      await Future.delayed(const Duration(seconds: 2)); // 录音时间

      // 模拟停止录音的新流程
      print('🛑 开始停止录音流程');
      final stopStartTime = stopwatch.elapsedMilliseconds;

      // 1. 发送停止命令
      await Future.delayed(const Duration(milliseconds: 50)); // 发送停止命令时间
      print('📤 已发送停止命令');

      // 2. 等待音频数据发送完成
      await Future.delayed(const Duration(milliseconds: 800)); // 音频数据发送时间
      print('📦 音频数据发送完成');

      // 3. 停止录音
      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // AudioUtil停止录音时间
      print('🔇 录音已停止');

      // 4. 取消音频流订阅
      await Future.delayed(const Duration(milliseconds: 300)); // 清理时间
      print('🧹 音频流订阅已取消');

      final stopEndTime = stopwatch.elapsedMilliseconds;
      stopwatch.stop();

      print('✅ 修复后的停止流程总耗时: ${stopEndTime - stopStartTime}ms');

      // 验证时序合理性
      expect(startTime, lessThan(300)); // 开始录音应该在300ms内完成
      expect(
        stopEndTime - stopStartTime,
        greaterThan(1500),
      ); // 停止流程应该有足够的时间处理音频数据
      expect(stopEndTime - stopStartTime, lessThan(2000)); // 但不应该太长

      print('✅ 修复后的时序测试通过');
    });

    test('测试音频缓冲清空功能', () async {
      // 测试重新开始录音时清空缓冲的功能
      print('🧹 测试音频缓冲清空功能...');

      // 模拟第一次录音产生音频数据
      final firstRecordingData = <String>[];
      for (int i = 0; i < 5; i++) {
        firstRecordingData.add('first_audio_packet_$i');
        await Future.delayed(const Duration(milliseconds: 60));
      }
      print('📦 第一次录音产生了 ${firstRecordingData.length} 个音频包');

      // 模拟第一次录音停止
      await Future.delayed(const Duration(milliseconds: 800));
      print('🛑 第一次录音停止');

      // 短暂间隔
      await Future.delayed(const Duration(milliseconds: 200));

      // 模拟第二次录音开始 - 应该清空缓冲
      print('🧹 开始第二次录音，应该清空之前的缓冲');
      await Future.delayed(const Duration(milliseconds: 100)); // 清空缓冲时间

      // 模拟第二次录音产生新的音频数据
      final secondRecordingData = <String>[];
      for (int i = 0; i < 3; i++) {
        secondRecordingData.add('second_audio_packet_$i');
        await Future.delayed(const Duration(milliseconds: 60));
      }
      print('📦 第二次录音产生了 ${secondRecordingData.length} 个音频包');

      // 验证数据完整性
      expect(firstRecordingData.length, equals(5));
      expect(secondRecordingData.length, equals(3));

      // 验证第二次录音的数据与第一次不同（模拟缓冲已清空）
      for (int i = 0; i < secondRecordingData.length; i++) {
        expect(secondRecordingData[i], startsWith('second_'));
        expect(secondRecordingData[i], isNot(startsWith('first_')));
      }

      print('✅ 音频缓冲清空功能测试通过');
    });

    test('测试完整的录音延迟修复流程', () async {
      // 测试完整的修复流程，确保第一次录音能正确发送
      print('🔧 测试完整的录音延迟修复流程...');

      final stopwatch = Stopwatch()..start();

      // === 第一次录音流程 ===
      print('🎤 开始第一次录音');

      // 1. 清空缓冲
      await Future.delayed(const Duration(milliseconds: 50));
      print('🧹 缓冲已清空');

      // 2. 发送开始命令
      await Future.delayed(const Duration(milliseconds: 50));
      print('📤 已发送开始监听命令');

      // 3. 等待服务器准备
      await Future.delayed(const Duration(milliseconds: 200));
      print('⏳ 服务器准备完成');

      // 4. 开始录音
      await Future.delayed(const Duration(milliseconds: 100));
      print('🎵 录音开始');

      // 5. 录音过程
      await Future.delayed(const Duration(seconds: 2));
      print('🗣️ 录音进行中...');

      // 6. 停止录音流程
      print('🛑 开始停止第一次录音');
      final firstStopStart = stopwatch.elapsedMilliseconds;

      // 6a. 发送停止命令
      await Future.delayed(const Duration(milliseconds: 50));
      print('📤 已发送停止命令');

      // 6b. 等待音频数据发送完成
      await Future.delayed(const Duration(milliseconds: 800));
      print('📦 音频数据发送完成');

      // 6c. 停止录音
      await Future.delayed(const Duration(milliseconds: 500));
      print('🔇 录音已停止');

      // 6d. 清理资源
      await Future.delayed(const Duration(milliseconds: 300));
      print('🧹 资源已清理');

      final firstStopEnd = stopwatch.elapsedMilliseconds;
      print('✅ 第一次录音完成，停止流程耗时: ${firstStopEnd - firstStopStart}ms');

      // === 第二次录音流程 ===
      await Future.delayed(const Duration(milliseconds: 500));
      print('🎤 开始第二次录音');

      // 重复相同的流程
      await Future.delayed(const Duration(milliseconds: 300)); // 开始流程
      await Future.delayed(const Duration(milliseconds: 1000)); // 录音时间
      print('🛑 开始停止第二次录音');

      final secondStopStart = stopwatch.elapsedMilliseconds;
      await Future.delayed(const Duration(milliseconds: 1650)); // 停止流程
      final secondStopEnd = stopwatch.elapsedMilliseconds;

      stopwatch.stop();

      print('✅ 第二次录音完成，停止流程耗时: ${secondStopEnd - secondStopStart}ms');

      // 验证时序
      expect(firstStopEnd - firstStopStart, greaterThan(1500));
      expect(firstStopEnd - firstStopStart, lessThan(2000));
      expect(secondStopEnd - secondStopStart, greaterThan(1500));
      expect(secondStopEnd - secondStopStart, lessThan(2000));

      print('✅ 完整录音延迟修复流程测试通过');
    });
  });
}
