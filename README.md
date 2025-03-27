# 小智AI助手 Android客户端

一个基于WebSocket的Android语音对话应用,支持实时语音交互和文字对话。
> (暂停更新单安卓端)现在全力输出计划flutter版本，打通IOS、Android、web端（pc端的可以自行调整，也能打包）。
> 请同志们动动小手，点点小星星，予以鼓励。目前只是伪修复回音，如果有大神PR，欢迎指教。

## 预告：
- 计划flutter版本打通iOS Android
- 实现添加Dify与小智服务
- 多个小智server添加
- 拟物化简洁UI

<table>
  <tr>
    <!-- 左侧单元格 -->
    <td align="center" valign="middle" height="500">
      <table>
        <tr>
          <td align="center">
            <img src="1740303422139.jpg" alt="小智AI助手界面预览" width="220" height="430"/>
          </td>
        </tr>
        <tr>
          <td align="center">
            <small>老版本安卓端演示图片</small>
          </td>
        </tr>
      </table>
    </td>
    <td align="center" valign="bottom" height="500">
      <table>
        <tr>
          <td align="center">
            <a href="https://www.bilibili.com/video/BV1fgXvYqE61" target="_blank">
              <img src="2345.jpg" alt="新版"  width="200" height="430"/>
            </a>
          </td>
        </tr>
        <tr>
          <td align="center">
            <small>
  新版IOS、安卓端（可以自行打包WEB、PC版本)<br>
  -- <a href="https://example.com" style="color: red; text-decoration: none;">观看demo视频点击跳转</a>
</small>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>

## 功能特点

- 实时语音电话对话
- 多服务地址添加
- 文字消息交互
- 波形动画显示
- 支持Opus音频编解码
- 支持Token认证
- 支持自定义MAC
- 自动重连机制
- 深色/浅色主题适配
- 随时打断，随时说话

## 系统要求

- Android 11.0 (API 30)及以上
- 需要麦克风权限
- 需要网络连接

## 构建说明

1. 克隆项目:
```bash
git clone https://github.com/TOM88812/xiaozhi-android-client.git
```

2. 使用Android Studio打开项目

3. 构建项目:
   - 点击 Build -> Build Bundle(s) / APK(s) -> Build APK(s)
   - 或在命令行执行: `./gradlew assembleDebug`

4. 编译输出:
   - Debug APK位置: `app/build/outputs/apk/debug/app-debug.apk`
   - Release APK位置: `app/build/outputs/apk/release/app-release.apk`

## 配置说明

1. 服务器配置
   - 在设置页面配置WebSocket服务器地址
   - 默认地址: `ws://localhost:9005`

2. Token认证
   - 可选择是否启用Token认证
   - 在设置页面配置Token

3. 自定义MAC
   - Android ID生成的MAC，或者自定义MAC
   - 在设置页面配置MAC
## 技术栈

- WebSocket: Java-WebSocket 1.5.4
- 音频编解码: Opus

## 开发环境

- Android Studio
- JDK 17

## 已知问题

- 目前对话基于音频输出活动，有活动时则闭麦，没有活动等待1s开启麦克风。伪回音消除

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=TOM88812/xiaozhi-android-client&type=Date)](https://star-history.com/#TOM88812/xiaozhi-android-client&Date)
