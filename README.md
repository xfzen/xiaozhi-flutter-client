# 小智AI助手 Android IOS 客户端

> 目前已经发布新版本，敬请体验！flutter IOS与安卓回音消除已实现，~~欢迎大家PR~~。
> 觉得项目对您有用的，可以赞赏一下，您的每一次赞赏都是我前进的动力。
> Dify支持发送图片交互。可以添加多个小智智能体到聊天列表。

一个基于WebSocket的Android语音对话应用,支持实时语音交互和文字对话。
基于Flutter框架开发的小智AI助手，支持多平台（iOS、Android、Web、Windows、macOS、Linux）部署，提供实时语音交互和文字对话功能。

<table>
  <tr>
    <td align="center" valign="bottom" height="500">
      <table>
        <tr>
          <td align="center">
            <a href="https://www.bilibili.com/video/BV178EqzAEFf" target="_blank">
              <img src="1234.jpg" alt="新版"  width="200" height="430"/>
            </a>
          </td>
        </tr>
        <tr>
          <td align="center">
            <small>
  新版IOS、安卓端（可以自行打包WEB、PC版本)<br>
  <a href="https://www.bilibili.com/video/BV1fgXvYqE61" style="color: red; text-decoration: none;">观看demo视频点击跳转</a>
</small>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>

# 近期出现不良社区风气，倒卖贩子泛滥，同时未对此开源项目做出署名，对开源社区造成严重影响，暂停开源推送。

## 功能特点（部分功能未在社区版实现）

- **跨平台支持**：使用Flutter框架，一套代码支持多平台
- **多AI模型支持**：
  - 集成小智AI服务
  - 支持Dify
  - 支持OpenAI-图文消息-流式输出
  - 支持官方小智-一键添加设备注册
- **丰富的交互方式**：
  - 支持实时语音通话（持续对话）
  - 支持文字消息交互
  - 支持图片消息
  - 支持通话手动打断
  - 支持按住说话
  - 支持实时语音打断
  - 支持添加多个智能体
  - 支持独特的心情交互
  - 支持视觉
  - 支持live2d（口型同步）
- **多样化界面**：
  - 深色/浅色主题适配
  - 轻度拟物化
  - 自适应UI布局
  - 精美动画效果
- **系统功能**：
  - 多种AI服务配置管理
  - 自动重连机制
  - 语音/文字会话混合历史
  - 安卓 AEC+NS 回音消除
  - iOS 回音消除
  - 支持Qwen3模型开关思考模式
  - 支持HTML代码预览

## 安装与构建

1. 克隆项目:
```bash
git clone https://github.com/TOM88812/xiaozhi-android-client.git
```

2. 安装依赖:
```bash
flutter pub get
```

3. 运行应用:
```bash
flutter run
```

4. 构建发布版本:
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## 配置说明

### 小智服务配置
- 支持配置多个小智服务地址
- OTA URL设置
- Token认证
- 自定义MAC
- wss地址自动获取

### Dify API配置
- 支持配置多个Dify服务
- API密钥管理
- 服务器URL配置

### OpenAI 服务
- 支持OpenAI接口
- 支持自定义模型
- 温度等配置

## 开发计划
- [x] 深色/浅色主题适配
- [x] 支持更多AI服务提供商
- [x] 增强语音识别准确性
- [x] 支持OTA自动注册设备
- [x] 支持语音实时打断
- [x] 支持Qwen3模型开关思考模式
- [x] 支持HTML代码预览
- [x] live2d 多模型自由切换
  - 内置两个live2d官方免费下载模型
  - live2d 自由导入
- [x] 支持iot功能
- [x] 支持视觉
- [x] 创新性心情模式
- [ ] 集成MIot 控制米家设备
- [ ] 支持TTS
- [ ] 支持MCP_Client
- [ ] 支持OpenAI接口联网搜索🔍

## 联系方式

> 全功能暂未在社区开放,全功能版目前仅对商业版提供。

- **email**
> lhht0606@163.com

- **wechat**
> Forever-Destin

## 服务端图形化部署工具
- https://space.bilibili.com/298384872
- https://znhblog.com/
## 微信交流群
<div style="display: flex;">
  <img width="350" src="https://camo.githubusercontent.com/542ebb2f6726fd2647d10f7aaca6131a14fec54b486041cb497f43d1da046d07/68747470733a2f2f7a6e68626c6f672e636f6d2f7374617469632f696d672f37636237363030396233323532666563373162633062363264393632383364612e2543332541352543322542452543322541452543332541342543322542462543322541312543332541352543322539422543322542452543332541372543322538392543322538375f32303235303531323030323332352e77656270" />
</div>


## 🌟支持

您的每一个start⭐或赞赏💖，都是我们不断前进的动力🛸。
<div style="display: flex;">
<img src="zsm.jpg" width="260" height="280" alt="赞助" style="border-radius: 12px;" />
</div>

# 赞助榜
- ### ***上海沃欧文化传媒有限公司***

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=TOM88812/xiaozhi-android-client&type=Date)](https://star-history.com/#TOM88812/xiaozhi-android-client&Date)
