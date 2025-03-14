package com.lhht.xiaozhi.utils;

import android.content.Context;
import android.content.SharedPreferences;
import android.provider.Settings;

public class DeviceUtils {
    private static final String PREFS_NAME = "device_settings";
    private static final String KEY_CUSTOM_MAC = "custom_mac";
    
    public static String getMacFromAndroidId(Context context) {
        // 先检查是否有自定义MAC
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String customMac = prefs.getString(KEY_CUSTOM_MAC, null);
        if (customMac != null) {
            return customMac.toUpperCase();
        }
        
        String androidId = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.ANDROID_ID);
        
        // 确保androidId长度为12个字符(去掉-号的MAC地址长度)
        StringBuilder macBuilder = new StringBuilder();
        
        // 如果androidId为null，使用默认值
        if (androidId == null) {
            androidId = "000000000000";
        }
        
        // 取androidId的前12位，如果不够则补0
        String processedId = (androidId + "000000000000").substring(0, 12);
        
        // 每2个字符插入一个:，形成MAC地址格式
        for (int i = 0; i < 12; i++) {
            macBuilder.append(processedId.charAt(i));
            if (i % 2 == 1 && i < 11) {
                macBuilder.append(":");
            }
        }
        
        return macBuilder.toString().toUpperCase();
    }
    
    public static void saveCustomMac(Context context, String mac) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putString(KEY_CUSTOM_MAC, mac).apply();
    }
    
    public static boolean isValidMacAddress(String mac) {
        if (mac == null) return false;
        // MAC地址格式验证：XX:XX:XX:XX:XX:XX
        return mac.matches("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$");
    }
} 