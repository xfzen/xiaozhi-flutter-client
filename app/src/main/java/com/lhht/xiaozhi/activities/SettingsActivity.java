package com.lhht.xiaozhi.activities;

import android.os.Bundle;
import android.view.MenuItem;
import android.widget.EditText;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton;
import com.google.android.material.switchmaterial.SwitchMaterial;
import com.google.android.material.textfield.TextInputEditText;
import com.lhht.xiaozhi.R;
import com.lhht.xiaozhi.settings.SettingsManager;
import com.lhht.xiaozhi.adapters.WsUrlAdapter;
import com.lhht.xiaozhi.utils.DeviceUtils;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

public class SettingsActivity extends AppCompatActivity {
    private SettingsManager settingsManager;
    private TextInputEditText tokenInput;
    private SwitchMaterial enableTokenSwitch;
    private RecyclerView wsUrlList;
    private MaterialButton addWsUrlButton;
    private WsUrlAdapter wsUrlAdapter;
    private EditText wsUrlInput;
    private EditText macInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        settingsManager = new SettingsManager(this);
        
        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        getSupportActionBar().setTitle("设置");

        tokenInput = findViewById(R.id.tokenInput);
        enableTokenSwitch = findViewById(R.id.tokenSwitch);
        ExtendedFloatingActionButton saveButton = findViewById(R.id.saveButton);
        wsUrlList = findViewById(R.id.wsUrlList);
        addWsUrlButton = findViewById(R.id.addWsUrlButton);
        wsUrlInput = findViewById(R.id.wsUrlInput);
        macInput = findViewById(R.id.macInput);

        // 加载当前设置
        wsUrlInput.setText(settingsManager.getWsUrl());
        tokenInput.setText(settingsManager.getToken());
        enableTokenSwitch.setChecked(settingsManager.isTokenEnabled());
        macInput.setText(DeviceUtils.getMacFromAndroidId(this));

        // 加载WebSocket地址列表
        Set<String> wsUrls = settingsManager.getWsUrls();
        if (wsUrls == null) {
            wsUrls = new HashSet<>();
            wsUrls.add(settingsManager.getWsUrl()); // 添加当前的URL
        }
        setupWsUrlList(new ArrayList<>(wsUrls), settingsManager.getWsUrl());

        // 根据Token开关状态更新Token输入框状态
        updateTokenInputState();
        enableTokenSwitch.setOnCheckedChangeListener((buttonView, isChecked) -> updateTokenInputState());

        // 添加新的WebSocket地址
        addWsUrlButton.setOnClickListener(v -> wsUrlAdapter.addUrl(""));

        // 保存设置
        saveButton.setOnClickListener(v -> {
            String wsUrl = wsUrlInput.getText().toString().trim();
            String token = tokenInput.getText().toString().trim();
            boolean enableToken = enableTokenSwitch.isChecked();
            String mac = macInput.getText().toString().trim();
            
            // 验证MAC地址格式
            if (!mac.isEmpty() && !DeviceUtils.isValidMacAddress(mac)) {
                Toast.makeText(this, "MAC地址格式无效，请使用XX:XX:XX:XX:XX:XX格式", Toast.LENGTH_LONG).show();
                return;
            }
            
            // 保存设置
            settingsManager.saveWsUrl(wsUrl);
            settingsManager.saveToken(token);
            settingsManager.setTokenEnabled(enableToken);
            if (!mac.isEmpty()) {
                DeviceUtils.saveCustomMac(this, mac);
            }
            
            Toast.makeText(this, "设置已保存", Toast.LENGTH_SHORT).show();
            finish();
        });
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            onBackPressed();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private void setupWsUrlList(ArrayList<String> urls, String currentUrl) {
        wsUrlList.setLayoutManager(new LinearLayoutManager(this));
        wsUrlAdapter = new WsUrlAdapter(urls, currentUrl, url -> wsUrlAdapter.removeUrl(url));
        wsUrlList.setAdapter(wsUrlAdapter);
    }

    private void updateTokenInputState() {
        tokenInput.setEnabled(enableTokenSwitch.isChecked());
    }
} 