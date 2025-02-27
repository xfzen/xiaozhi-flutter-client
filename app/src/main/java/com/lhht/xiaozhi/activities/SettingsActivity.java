package com.lhht.xiaozhi.activities;

import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Switch;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.lhht.xiaozhi.R;
import com.lhht.xiaozhi.settings.SettingsManager;
import com.lhht.xiaozhi.adapters.WsUrlAdapter;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

public class SettingsActivity extends AppCompatActivity {
    private SettingsManager settingsManager;
    private EditText tokenInput;
    private Switch enableTokenSwitch;
    private RecyclerView wsUrlList;
    private Button addWsUrlButton;
    private WsUrlAdapter wsUrlAdapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        settingsManager = new SettingsManager(this);
        
        tokenInput = findViewById(R.id.tokenInput);
        enableTokenSwitch = findViewById(R.id.enableTokenSwitch);
        Button saveButton = findViewById(R.id.saveButton);
        wsUrlList = findViewById(R.id.wsUrlList);
        addWsUrlButton = findViewById(R.id.addWsUrlButton);

        // 加载当前设置
        tokenInput.setText(settingsManager.getToken());
        enableTokenSwitch.setChecked(settingsManager.isTokenEnabled());

        // 加载WebSocket地址列表
        Set<String> wsUrls = settingsManager.getWsUrls();
        if (wsUrls == null) {
            wsUrls = new HashSet<>();
            wsUrls.add(settingsManager.getWsUrl()); // 添加当前的URL
        }
        setupWsUrlList(new ArrayList<>(wsUrls));

        // 根据Token开关状态更新Token输入框状态
        updateTokenInputState();
        enableTokenSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> updateTokenInputState());

        // 添加新的WebSocket地址
        addWsUrlButton.setOnClickListener(v -> wsUrlAdapter.addUrl(""));

        // 保存设置
        saveButton.setOnClickListener(v -> {
            String token = tokenInput.getText().toString();
            boolean enableToken = enableTokenSwitch.isChecked();

            // 获取当前所有WebSocket地址
            ArrayList<String> currentUrls = wsUrlAdapter.getUrls();

            // 获取第一个非空地址作为当前选中的地址
            String selectedWsUrl = null;
            for (String url : currentUrls) {
                if (!url.isEmpty()) {
                    selectedWsUrl = url;
                    break;
                }
            }
            if (selectedWsUrl != null) {
                settingsManager.saveSettings(selectedWsUrl, token, enableToken);
            }
            settingsManager.saveWsUrls(new HashSet<>(currentUrls));
            finish();
        });
    }

    private void setupWsUrlList(ArrayList<String> urls) {
        wsUrlList.setLayoutManager(new LinearLayoutManager(this));
        wsUrlAdapter = new WsUrlAdapter(urls, url -> wsUrlAdapter.removeUrl(url));
        wsUrlList.setAdapter(wsUrlAdapter);
    }

    private void updateTokenInputState() {
        tokenInput.setEnabled(enableTokenSwitch.isChecked());
    }
} 