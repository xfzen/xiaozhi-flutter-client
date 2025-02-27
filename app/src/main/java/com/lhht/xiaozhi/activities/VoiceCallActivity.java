package com.lhht.xiaozhi.activities;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.lhht.xiaozhi.R;
import com.lhht.xiaozhi.settings.SettingsManager;
import com.lhht.xiaozhi.views.WaveformView;
import com.lhht.xiaozhi.websocket.WebSocketManager;
import vip.inode.demo.opusaudiodemo.utils.OpusUtils;

import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class VoiceCallActivity extends AppCompatActivity implements WebSocketManager.WebSocketListener {
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO;
    private static final int AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT;
    private static final int BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT);
    private static final int PLAY_BUFFER_SIZE = 65536;
    private static final int OPUS_FRAME_SIZE = 960;

    private TextView aiMessageText;
    private TextView recognizedText;
    private TextView callStatusText;
    private TextView emojiText;
    private WaveformView aiWaveformView;
    private WaveformView userWaveformView;
    private ImageButton muteButton;
    private ImageButton hangupButton;
    private ImageButton speakerButton;
    
    private boolean isMuted = false;
    private boolean isSpeakerOn = false;
    private boolean isRecording = false;
    private boolean isPlaying = false;
    
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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // 设置沉浸式状态栏和导航栏
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE |
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        );
        
        setContentView(R.layout.activity_voice_call);
        
        initViews();
        initWebSocket();
        initAudio();
        setupListeners();
    }

    private void initViews() {
        aiMessageText = findViewById(R.id.aiMessageText);
        recognizedText = findViewById(R.id.recognizedText);
        callStatusText = findViewById(R.id.callStatusText);
        emojiText = findViewById(R.id.emojiText);
        aiWaveformView = findViewById(R.id.aiWaveformView);
        userWaveformView = findViewById(R.id.userWaveformView);
        muteButton = findViewById(R.id.muteButton);
        hangupButton = findViewById(R.id.hangupButton);
        speakerButton = findViewById(R.id.speakerButton);
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
        encoderHandle = opusUtils.createEncoder(SAMPLE_RATE, 1, 10);
        decoderHandle = opusUtils.createDecoder(SAMPLE_RATE, 1);
        decodedBuffer = new short[OPUS_FRAME_SIZE];
        recordBuffer = new short[OPUS_FRAME_SIZE];
        
        // 初始化音频播放器
        initAudioTrack();
    }

    private void initAudioTrack() {
        try {
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
        } catch (Exception e) {
            Log.e("VoiceCall", "创建AudioTrack失败", e);
        }
    }

    private void setupListeners() {
        muteButton.setOnClickListener(v -> toggleMute());
        hangupButton.setOnClickListener(v -> endCall());
        speakerButton.setOnClickListener(v -> toggleSpeaker());

        // 点击屏幕打断AI回答
        View rootView = findViewById(android.R.id.content);
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
            audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                BUFFER_SIZE
            );
        }

        executorService.execute(() -> {
            try {
                audioRecord.startRecording();
                byte[] buffer = new byte[BUFFER_SIZE];
                
                while (isRecording) {
                    int read = audioRecord.read(buffer, 0, BUFFER_SIZE);
                    if (read > 0 && !isMuted) {
                        // 发送音频数据
                        sendAudioData(buffer, read);
                        // 更新波形图
                        updateUserWaveform(buffer);
                    }
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "录音失败", e);
            }
        });
    }

    private void sendAudioData(byte[] data, int size) {
        if (webSocketManager != null && webSocketManager.isConnected()) {
            try {
                // 将byte[]转换为short[]
                short[] samples = new short[size / 2];
                for (int i = 0; i < samples.length; i++) {
                    samples[i] = (short) ((data[i * 2] & 0xFF) | (data[i * 2 + 1] << 8));
                }
                
                // 编码音频数据
                byte[] encodedData = new byte[size];
                int encodedSize = opusUtils.encode(encoderHandle, samples, 0, encodedData);
                if (encodedSize > 0) {
                    // 直接发送编码后的音频数据
                    byte[] encodedBytes = new byte[encodedSize];
                    System.arraycopy(encodedData, 0, encodedBytes, 0, encodedSize);
                    webSocketManager.sendBinaryMessage(encodedBytes);
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
                jsonMessage.put("type", "interrupt");
                webSocketManager.sendMessage(jsonMessage.toString());
                updateCallStatus("已打断AI回答");
            } catch (Exception e) {
                Log.e("VoiceCall", "发送中断消息失败", e);
            }
        }
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
        if (userWaveformView != null) {
            float[] amplitudes = new float[buffer.length / 2];
            for (int i = 0; i < amplitudes.length; i++) {
                short sample = (short) ((buffer[i * 2] & 0xFF) | (buffer[i * 2 + 1] << 8));
                amplitudes[i] = sample / 32768f;
            }
            runOnUiThread(() -> userWaveformView.setAmplitudes(amplitudes));
        }
    }

    public void updateAiWaveform(float[] amplitudes) {
        runOnUiThread(() -> {
            if (aiWaveformView != null) {
                aiWaveformView.setAmplitudes(amplitudes);
            }
        });
    }

    @Override
    public void onConnected() {
        updateCallStatus("已连接");
        startCall();
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
            
            switch (type) {
                case "stt":
                    // 处理语音识别结果
                    String recognizedText = jsonMessage.getString("text");
                    updateRecognizedText(recognizedText);
                    break;
                    
                case "tts":
                    handleTTSMessage(jsonMessage);
                    break;
            }
        } catch (Exception e) {
            Log.e("VoiceCall", "处理消息失败", e);
        }
    }

    private void handleTTSMessage(JSONObject message) {
        try {
            String state = message.getString("state");
            switch (state) {
                case "start":
                    // AI开始说话
                    updateCallStatus("AI正在说话...");
                    break;
                    
                case "sentence_start":
                    // 显示AI说的话
                    String text = message.getString("text");
                    // 分离emoji和文本
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
                    updateCallStatus("AI正在说话...");
                    break;
                    
                case "end":
                    // AI说话结束
                    updateCallStatus("正在通话中...");
                    hideEmoji();
                    break;
                    
                case "error":
                    String error = message.optString("error", "未知错误");
                    updateCallStatus("TTS错误: " + error);
                    hideEmoji();
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

                if (!isPlaying) {
                    audioTrack.play();
                    isPlaying = true;
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
                    audioTrack.write(pcmData, 0, pcmData.length, AudioTrack.WRITE_BLOCKING);
                    
                    // 更新AI波形图
                    float[] amplitudes = new float[decodedSamples];
                    for (int i = 0; i < decodedSamples; i++) {
                        amplitudes[i] = decodedBuffer[i] / 32768f;
                    }
                    updateAiWaveform(amplitudes);
                }
            } catch (Exception e) {
                Log.e("VoiceCall", "处理音频数据失败", e);
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
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
    }
} 