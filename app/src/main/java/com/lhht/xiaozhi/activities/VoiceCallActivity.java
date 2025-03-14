package com.lhht.xiaozhi.activities;

import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.lhht.xiaozhi.R;
import com.lhht.xiaozhi.settings.SettingsManager;
import com.lhht.xiaozhi.views.RippleWaveView;
import com.lhht.xiaozhi.websocket.WebSocketManager;
import vip.inode.demo.opusaudiodemo.utils.OpusUtils;
import com.skydoves.colorpickerview.ColorPickerDialog;
import com.skydoves.colorpickerview.ColorEnvelope;
import com.skydoves.colorpickerview.listeners.ColorEnvelopeListener;

import org.json.JSONObject;
import java.lang.reflect.Field;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class VoiceCallActivity extends AppCompatActivity implements WebSocketManager.WebSocketListener {
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO;
    private static final int AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT;
    private static final int BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT);
    private static final int PLAY_BUFFER_SIZE = 65536;
    private static final int OPUS_FRAME_SIZE = 960;
    private static final int OPUS_FRAME_DURATION = 60; // 60ms per frame
    private static final long UI_UPDATE_TIMEOUT = 1500;  // 1.5秒无声音就更新UI
    private static final long MIC_ENABLE_DELAY = 1000;   // UI更新1秒后开启麦克风
    private static final long CHECK_INTERVAL = 50;       // 检测频率提高到50ms

    private TextView aiMessageText;
    private TextView recognizedText;
    private TextView callStatusText;
    private TextView emojiText;
    private RippleWaveView rippleView;
    private ImageButton muteButton;
    private ImageButton hangupButton;
    private ImageButton speakerButton;
    private ImageButton colorPickerButton;
    private View rootView;
    private View backgroundView;
    private View topBar;
    private View controlButtons;
    private int currentBackgroundColor;
    
    private boolean isMuted = false;
    private boolean isSpeakerOn = true;
    private boolean isRecording = false;
    private boolean isPlaying = false;
    private volatile boolean isDestroyed = false;
    
    private AudioRecord audioRecord;
    private AudioTrack audioTrack;
    private ExecutorService executorService;
    private ExecutorService audioExecutor;
    private Handler mainHandler;
    private WebSocketManager webSocketManager;
    private OpusUtils opusUtils;
    private long encoderHandle;
    private long decoderHandle;
    private short[] decodedBuffer;
    private short[] recordBuffer;
    private byte[] encodedBuffer;
    private boolean hasStartedCall = false;
    private String sessionId = "";  // 添加session_id字段
    private long lastPlaybackPosition = 0;
    private int samePositionCount = 0;
    private long lastAudioDataTime = 0;  // 新增：记录最后一次收到音频数据的时间
    private boolean isCheckingPlaybackStatus = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 设置沉浸式状态栏和导航栏
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS | WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);

        setContentView(R.layout.activity_voice_call);
        
        // 获取实际的状态栏高度并设置topBar的margin
        View topBar = findViewById(R.id.topBar);
        if (topBar != null) {
            int statusBarHeight = 0;
            int resourceId = getResources().getIdentifier("status_bar_height", "dimen", "android");
            if (resourceId > 0) {
                statusBarHeight = getResources().getDimensionPixelSize(resourceId);
            }
            ((ViewGroup.MarginLayoutParams) topBar.getLayoutParams()).topMargin = statusBarHeight;
            topBar.requestLayout();
        }
        
        // 获取实际的导航栏高度并设置bottomBar的margin
        View controlButtons = findViewById(R.id.controlButtons);
        if (controlButtons != null) {
            int navigationBarHeight = 0;
            int resourceId = getResources().getIdentifier("navigation_bar_height", "dimen", "android");
            if (resourceId > 0) {
                navigationBarHeight = getResources().getDimensionPixelSize(resourceId);
            }
            ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) controlButtons.getLayoutParams();
            params.bottomMargin = navigationBarHeight + 48;
            controlButtons.setLayoutParams(params);
        }
        
        initViews();
        initAudio();
        setupListeners();
        initWebSocket();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
    }

    private void hideSystemUI() {
        View decorView = getWindow().getDecorView();
        decorView.setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE |
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
            View.SYSTEM_UI_FLAG_FULLSCREEN
        );
    }

    private void initViews() {
        // 先从设置中读取保存的颜色
        SettingsManager settingsManager = new SettingsManager(this);
        currentBackgroundColor = settingsManager.getBackgroundColor(Color.BLACK);

        aiMessageText = findViewById(R.id.aiMessageText);
        recognizedText = findViewById(R.id.recognizedText);
        callStatusText = findViewById(R.id.callStatusText);
        emojiText = findViewById(R.id.emojiText);
        rippleView = findViewById(R.id.rippleView);
        muteButton = findViewById(R.id.muteButton);
        hangupButton = findViewById(R.id.hangupButton);
        speakerButton = findViewById(R.id.speakerButton);
        colorPickerButton = findViewById(R.id.colorPickerButton);
        rootView = findViewById(R.id.rootLayout);
        backgroundView = findViewById(R.id.backgroundView);
        topBar = findViewById(R.id.topBar);
        controlButtons = findViewById(R.id.controlButtons);
        
        // 获取状态栏高度
        int statusBarHeight = 0;
        int resourceId = getResources().getIdentifier("status_bar_height", "dimen", "android");
        if (resourceId > 0) {
            statusBarHeight = getResources().getDimensionPixelSize(resourceId);
        }
        
        // 获取导航栏高度
        int navigationBarHeight = 0;
        resourceId = getResources().getIdentifier("navigation_bar_height", "dimen", "android");
        if (resourceId > 0) {
            navigationBarHeight = getResources().getDimensionPixelSize(resourceId);
        }

        // 设置顶部和底部边距
        ViewGroup.MarginLayoutParams topParams = (ViewGroup.MarginLayoutParams) topBar.getLayoutParams();
        topParams.topMargin = statusBarHeight;
        topBar.setLayoutParams(topParams);

        ViewGroup.MarginLayoutParams bottomParams = (ViewGroup.MarginLayoutParams) controlButtons.getLayoutParams();
        bottomParams.bottomMargin = navigationBarHeight;
        controlButtons.setLayoutParams(bottomParams);

        // 设置初始背景色
        backgroundView.setBackgroundColor(currentBackgroundColor);
    }

    private void initWebSocket() {
        // 从MainActivity获取WebSocket配置
        String deviceId = Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID);
        SettingsManager settingsManager = new SettingsManager(this);
        String wsUrl = settingsManager.getWsUrl();
        String token = settingsManager.getToken();
        boolean enableToken = settingsManager.isTokenEnabled();

        webSocketManager = new WebSocketManager(deviceId);
        webSocketManager.setListener(this);

        // 连接WebSocket
        try {
            webSocketManager.connect(wsUrl, token, enableToken);
            updateCallStatus("正在连接...");
        } catch (Exception e) {
            Log.e("VoiceCall", "WebSocket连接失败", e);
            updateCallStatus("连接失败");
            Toast.makeText(this, "连接失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
            finish();
        }
    }

    private void initAudio() {
        executorService = Executors.newSingleThreadExecutor();
        audioExecutor = Executors.newSingleThreadExecutor();
        mainHandler = new Handler(Looper.getMainLooper());
        
        // 初始化Opus编解码器
        opusUtils = OpusUtils.getInstance();
        // 使用OPUS_APPLICATION_VOIP模式，设置比特率为32000
        encoderHandle = opusUtils.createEncoder(SAMPLE_RATE, 1, 32000);
        decoderHandle = opusUtils.createDecoder(SAMPLE_RATE, 1);
        decodedBuffer = new short[OPUS_FRAME_SIZE];
        recordBuffer = new short[OPUS_FRAME_SIZE];
        encodedBuffer = new byte[OPUS_FRAME_SIZE * 2];
        
        // 设置音频模式
        AudioManager audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
        audioManager.setSpeakerphoneOn(true);
        
        // 初始化音频播放器
        initAudioTrack();
    }

    private void initAudioTrack() {
        try {
            if (audioTrack != null) {
                audioTrack.release();
            }

            audioTrack = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                .setAudioFormat(new AudioFormat.Builder()
                    .setEncoding(AUDIO_FORMAT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build())
                .setBufferSizeInBytes(PLAY_BUFFER_SIZE)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build();

            audioTrack.play();
        } catch (Exception e) {
            Log.e("VoiceCall", "创建AudioTrack失败", e);
        }
    }

    private void setupListeners() {
        muteButton.setOnClickListener(v -> toggleMute());
        hangupButton.setOnClickListener(v -> endCall());
        speakerButton.setOnClickListener(v -> toggleSpeaker());
        colorPickerButton.setOnClickListener(v -> showColorPicker());

        // 点击屏幕打断AI回答
        rootView.setOnClickListener(v -> interruptAiResponse());
    }

    private void startCall() {
        if (!webSocketManager.isConnected()) {
            updateCallStatus("未连接");
            return;
        }

        try {
            // 发送开始通话消息
            JSONObject startMessage = new JSONObject();
            startMessage.put("type", "start");
            startMessage.put("mode", "auto");
            startMessage.put("audio_params", new JSONObject()
                .put("format", "opus")
                .put("sample_rate", SAMPLE_RATE)
                .put("channels", 1)
                .put("frame_duration", 60));
            webSocketManager.sendMessage(startMessage.toString());

            // 开始录音
            isRecording = true;
            startRecording();
            updateCallStatus("正在通话中...");
        } catch (Exception e) {
            Log.e("VoiceCall", "开始通话失败", e);
            updateCallStatus("开始通话失败");
        }
    }

    private void startRecording() {
        if (audioRecord == null) {
            try {
                audioRecord = new AudioRecord.Builder()
                    .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                    .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AUDIO_FORMAT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(CHANNEL_CONFIG)
                        .build())
                    .setBufferSizeInBytes(BUFFER_SIZE)
                    .build();
                
                if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                    Log.e("VoiceCall", "AudioRecord初始化失败");
                    return;
                }
                
                Log.d("VoiceCall", "AudioRecord 初始化成功，缓冲区大小: " + BUFFER_SIZE);
            } catch (Exception e) {
                Log.e("VoiceCall", "创建AudioRecord失败", e);
                return;
            }
        }

        executorService.execute(() -> {
            try {
                audioRecord.startRecording();
                Log.d("VoiceCall", "开始录音");
                
                while (!isDestroyed) {
                    if (!isRecording || isMuted) {
                        // 如果不在录音状态或静音，暂停一下
                        Thread.sleep(100);
                        continue;
                    }
                    
                    int read = audioRecord.read(recordBuffer, 0, OPUS_FRAME_SIZE);
                    if (read > 0) {
                        sendAudioData(recordBuffer, read);
                    } else if (read < 0) {
                        Log.e("VoiceCall", "读取音频数据失败: " + read);
                        break;
                    }
                    
                    // 控制采样率
                    Thread.sleep(OPUS_FRAME_DURATION);
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "录音失败", e);
            }
        });
    }

    private void sendAudioData(short[] data, int size) {
        if (webSocketManager != null && webSocketManager.isConnected() && !isMuted) {
            try {
                // 编码音频数据
                int encodedSize = opusUtils.encode(encoderHandle, data, 0, encodedBuffer);
                if (encodedSize > 0) {
                    byte[] encodedData = new byte[encodedSize];
                    System.arraycopy(encodedBuffer, 0, encodedData, 0, encodedSize);
                    
                    // 检查是否全是静音数据
                    boolean isAllZero = true;
                    for (int i = 0; i < size && isAllZero; i++) {
                        if (data[i] != 0) {
                            isAllZero = false;
                        }
                    }
                    
                    if (!isAllZero) {
                        webSocketManager.sendBinaryMessage(encodedData);
                        Log.d("VoiceCall", "发送音频数据: " + encodedSize + " bytes");
                        
                        // 更新波形图
                        byte[] buffer = new byte[size * 2];
                        for (int i = 0; i < size; i++) {
                            buffer[i * 2] = (byte) (data[i] & 0xFF);
                            buffer[i * 2 + 1] = (byte) ((data[i] >> 8) & 0xFF);
                        }
                        updateUserWaveform(buffer);
                    }
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "发送音频数据失败", e);
            }
        }
    }

    private void toggleMute() {
        isMuted = !isMuted;
        muteButton.setImageResource(isMuted ? R.drawable.ic_mic_off : R.drawable.ic_mic);
        updateCallStatus(isMuted ? "已静音" : "正在通话中...");
    }

    private void toggleSpeaker() {
        isSpeakerOn = !isSpeakerOn;
        speakerButton.setImageResource(isSpeakerOn ? R.drawable.ic_volume_up : R.drawable.ic_volume_off);
        
        AudioManager audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        // 保持在通话模式
        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
        audioManager.setSpeakerphoneOn(isSpeakerOn);
    }

    private void endCall() {
        isRecording = false;
        if (audioRecord != null) {
            audioRecord.stop();
            audioRecord.release();
            audioRecord = null;
        }
        if (audioTrack != null) {
            audioTrack.stop();
            audioTrack.release();
            audioTrack = null;
        }
        finish();
    }

    private void interruptAiResponse() {
        if (webSocketManager != null && webSocketManager.isConnected()) {
            try {
                JSONObject jsonMessage = new JSONObject();
                jsonMessage.put("type", "abort");
                jsonMessage.put("reason", "user_interrupted");
                webSocketManager.sendMessage(jsonMessage.toString());
                updateCallStatus("已打断AI回答");
                
                // 停止当前音频播放
                stopCurrentAudio();
            } catch (Exception e) {
                Log.e("VoiceCall", "发送中断消息失败", e);
            }
        }
    }

    private void stopCurrentAudio() {
        audioExecutor.execute(() -> {
            try {
                if (audioTrack != null && isPlaying) {
                    audioTrack.pause();
                    audioTrack.flush();
                    isPlaying = false;
                    // 清空波形显示
                    updateAiWaveform(new float[0]);
                    // 重新初始化AudioTrack
                    initAudioTrack();
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "停止音频播放失败", e);
            }
        });
    }

    public void updateCallStatus(String status) {
        runOnUiThread(() -> {
            if (callStatusText != null) {
                callStatusText.setText(status);
            }
        });
    }

    public void updateAiMessage(String message) {
        runOnUiThread(() -> {
            if (aiMessageText != null) {
                aiMessageText.setText(message);
            }
        });
    }

    public void updateRecognizedText(String text) {
        runOnUiThread(() -> {
            if (recognizedText != null) {
                recognizedText.setText(text);
            }
        });
    }

    private void updateUserWaveform(byte[] buffer) {
        if (rippleView != null) {
            float maxAmplitude = 0;
            for (int i = 0; i < buffer.length; i += 2) {
                short sample = (short) ((buffer[i] & 0xFF) | (buffer[i + 1] << 8));
                maxAmplitude = Math.max(maxAmplitude, Math.abs(sample / 32768f));
            }
            rippleView.setAmplitude(maxAmplitude);
        }
    }

    public void updateAiWaveform(float[] amplitudes) {
        if (amplitudes != null && amplitudes.length > 0) {
            final float maxAmplitude = calculateMaxAmplitude(amplitudes);
            runOnUiThread(() -> {
                if (rippleView != null) {
                    rippleView.setAmplitude(maxAmplitude);
                }
            });
        }
    }

    private float calculateMaxAmplitude(float[] amplitudes) {
        float maxAmplitude = 0;
        for (float amplitude : amplitudes) {
            maxAmplitude = Math.max(maxAmplitude, Math.abs(amplitude));
        }
        return maxAmplitude;
    }

    @Override
    public void onConnected() {
        updateCallStatus("已连接");
        // 发送hello消息
    }

    @Override
    public void onDisconnected() {
        updateCallStatus("连接已断开");
        endCall();
    }

    @Override
    public void onError(String error) {
        updateCallStatus("错误: " + error);
    }

    @Override
    public void onMessage(String message) {
        try {
            JSONObject jsonMessage = new JSONObject(message);
            String type = jsonMessage.getString("type");
            Log.d("VoiceCall", "收到消息: " + message);
            
            switch (type) {
                case "stt":
                    // 处理语音识别结果
                    String recognizedText = jsonMessage.getString("text");
                    updateRecognizedText(recognizedText);
                    break;
                    
                case "tts":
                    handleTTSMessage(jsonMessage);
                    break;
                    
                case "hello":
                    // 处理服务器的hello响应
                    if (!hasStartedCall) {
                        // 等待服务器返回session_id
                        if (jsonMessage.has("session_id")) {
                            sessionId = jsonMessage.getString("session_id");
                            hasStartedCall = true;
                            startCall();
                        }
                    }
                    break;

                case "start":
                    // 收到start响应后，发送listen消息
                    if (jsonMessage.has("session_id")) {
                        sessionId = jsonMessage.getString("session_id");
                        sendListenMessage();
                    }
                    break;
            }
        } catch (Exception e) {
            Log.e("VoiceCall", "处理消息失败", e);
        }
    }

    private void sendListenMessage() {
        try {
            JSONObject listenMessage = new JSONObject();
            listenMessage.put("type", "listen");
            listenMessage.put("session_id", sessionId);
            listenMessage.put("state", "start");
            listenMessage.put("mode", "auto");
            webSocketManager.sendMessage(listenMessage.toString());
            Log.d("VoiceCall", "发送listen消息");

            // 开始录音
            isRecording = true;
            startRecording();
            updateCallStatus("正在通话中...");
        } catch (Exception e) {
            Log.e("VoiceCall", "发送listen消息失败", e);
        }
    }

    private void handleTTSMessage(JSONObject message) {
        try {
            String state = message.getString("state");
            switch (state) {
                case "sentence_start":
                    // 分离emoji和文本
                    String text = message.getString("text");
                    String[] parts = extractEmojiAndText(text);
                    String emoji = parts[0];
                    String cleanText = parts[1];
                    
                    // 更新AI文本（不含emoji）
                    updateAiMessage(cleanText);
                    
                    // 显示emoji（如果有）
                    if (!emoji.isEmpty()) {
                        showEmoji(emoji);
                    } else {
                        hideEmoji();
                    }
                    break;
                    
                case "error":
                    String error = message.optString("error", "未知错误");
                    Log.e("VoiceCall", "TTS错误: " + error);
                    break;
            }
        } catch (Exception e) {
            Log.e("VoiceCall", "处理TTS消息失败", e);
        }
    }

    private String[] extractEmojiAndText(String text) {
        StringBuilder emoji = new StringBuilder();
        StringBuilder cleanText = new StringBuilder();
        
        int length = text.length();
        for (int i = 0; i < length; ) {
            int codePoint = text.codePointAt(i);
            int charCount = Character.charCount(codePoint);
            
            // 检查是否是emoji（Unicode范围）
            if ((codePoint >= 0x1F300 && codePoint <= 0x1F9FF) ||  // Emoji
                (codePoint >= 0x2600 && codePoint <= 0x26FF) ||    // Misc Symbols
                (codePoint >= 0x2700 && codePoint <= 0x27BF) ||    // Dingbats
                (codePoint >= 0xFE00 && codePoint <= 0xFE0F) ||    // Variation Selectors
                (codePoint >= 0x1F900 && codePoint <= 0x1F9FF)) {  // Supplemental Symbols and Pictographs
                emoji.append(new String(Character.toChars(codePoint)));
            } else {
                cleanText.append(new String(Character.toChars(codePoint)));
            }
            i += charCount;
        }
        
        return new String[]{emoji.toString(), cleanText.toString().trim()};
    }

    private void showEmoji(String emoji) {
        runOnUiThread(() -> {
            if (emojiText != null) {
                emojiText.setText(emoji);
                emojiText.setVisibility(View.VISIBLE);
            }
        });
    }

    private void hideEmoji() {
        runOnUiThread(() -> {
            if (emojiText != null) {
                emojiText.setVisibility(View.GONE);
            }
        });
    }

    @Override
    public void onBinaryMessage(byte[] data) {
        if (data == null || data.length == 0) return;
        
        audioExecutor.execute(() -> {
            try {
                if (audioTrack == null || audioTrack.getState() != AudioTrack.STATE_INITIALIZED) {
                    initAudioTrack();
                }

                // 解码并播放音频数据
                int decodedSamples = opusUtils.decode(decoderHandle, data, decodedBuffer);
                if (decodedSamples > 0) {
                    byte[] pcmData = new byte[decodedSamples * 2];
                    for (int i = 0; i < decodedSamples; i++) {
                        short sample = decodedBuffer[i];
                        pcmData[i * 2] = (byte) (sample & 0xff);
                        pcmData[i * 2 + 1] = (byte) ((sample >> 8) & 0xff);
                    }
                    
                    // 更新最后一次收到音频数据的时间
                    lastAudioDataTime = System.currentTimeMillis();
                    
                    // 如果之前不是AI说话状态，则立即切换状态并关闭麦克风
                    if (!isPlaying) {
                        isPlaying = true;
                        isRecording = false;  // 立即关闭麦克风
                        updateCallStatus("AI正在说话...");
                    }
                    
                    int written = audioTrack.write(pcmData, 0, pcmData.length, AudioTrack.WRITE_BLOCKING);
                    if (written < 0) {
                        Log.e("VoiceCall", "音频播放失败: " + written);
                    }
                    
                    // 更新AI波形图
                    float[] amplitudes = new float[decodedSamples];
                    for (int i = 0; i < decodedSamples; i++) {
                        amplitudes[i] = decodedBuffer[i] / 32768f;
                    }
                    updateAiWaveform(amplitudes);

                    // 确保状态检查在运行
                    if (!isCheckingPlaybackStatus) {
                        startPlaybackStatusCheck();
                    }
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "处理音频数据失败", e);
            }
        });
    }

    private void startPlaybackStatusCheck() {
        isCheckingPlaybackStatus = true;
        checkPlaybackStatus();
    }

    private void checkPlaybackStatus() {
        if (audioTrack != null && isPlaying) {
            long currentTime = System.currentTimeMillis();
            long timeSinceLastAudio = currentTime - lastAudioDataTime;
            
            // 如果超过1.5秒没有收到新的音频数据，更新UI
            if (timeSinceLastAudio > UI_UPDATE_TIMEOUT) {
                isPlaying = false;
                updateCallStatus("正在通话中...");
                hideEmoji();
                Log.d("VoiceCall", "AI说话结束，更新UI状态");
                
                // 延迟1秒后开启麦克风
                mainHandler.postDelayed(() -> {
                    if (!isPlaying) {  // 再次检查是否还是非播放状态
                        isRecording = true;
                        Log.d("VoiceCall", "延迟开启麦克风");
                    }
                }, MIC_ENABLE_DELAY);
                
                isCheckingPlaybackStatus = false;
                return;
            }
            
            // 继续检查，提高检查频率
            mainHandler.postDelayed(() -> checkPlaybackStatus(), CHECK_INTERVAL);
        } else {
            isCheckingPlaybackStatus = false;
        }
    }

    private void showColorPicker() {
        new ColorPickerDialog.Builder(this)
            .setTitle("选择背景颜色")
            .setPreferenceName("MyColorPickerDialog")
            .setPositiveButton("确定", 
                (ColorEnvelopeListener) (envelope, fromUser) -> {
                    currentBackgroundColor = envelope.getColor();
                    backgroundView.setBackgroundColor(currentBackgroundColor);
                    // 保存颜色设置
                    SettingsManager settingsManager = new SettingsManager(this);
                    settingsManager.saveBackgroundColor(currentBackgroundColor);
                })
            .setNegativeButton("取消", 
                (dialogInterface, i) -> dialogInterface.dismiss())
            .attachAlphaSlideBar(true)
            .attachBrightnessSlideBar(true)
            .setBottomSpace(12)
            .show();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        isDestroyed = true;
        hasStartedCall = false;
        
        if (webSocketManager != null) {
            try {
                JSONObject endMessage = new JSONObject();
                endMessage.put("type", "end");
                webSocketManager.sendMessage(endMessage.toString());
            } catch (Exception e) {
                Log.e("VoiceCall", "发送结束消息失败", e);
            }
            webSocketManager.disconnect();
        }
        
        endCall();
        
        if (encoderHandle != 0) {
            opusUtils.destroyEncoder(encoderHandle);
            encoderHandle = 0;
        }
        if (decoderHandle != 0) {
            opusUtils.destroyDecoder(decoderHandle);
            decoderHandle = 0;
        }
        
        executorService.shutdown();
        audioExecutor.shutdown();
        
        // 恢复音频模式
        AudioManager audioManager = (AudioManager) getSystemService(AUDIO_SERVICE);
        audioManager.setMode(AudioManager.MODE_NORMAL);
        audioManager.setSpeakerphoneOn(false);

        isCheckingPlaybackStatus = false;
    }
}