package com.lhht.xiaozhi.models.websokcet.send.core;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * @author chenguijian
 * @since 2025/3/21
 */
public final class WebSocketSendMsgDataFactory {

    private static class WebSocketMessageFactoryHolder {
        private static final WebSocketSendMsgDataFactory INSTANCE = new WebSocketSendMsgDataFactory();
    }

    private WebSocketSendMsgDataFactory() {

    }

    public static WebSocketSendMsgDataFactory getInstance() {
        return WebSocketMessageFactoryHolder.INSTANCE;
    }


    public JSONObject createHelloMsg() throws JSONException {
        JSONObject hello = new JSONObject();
        hello.put("type", "hello");
        hello.put("version", 3);
        hello.put("transport", "websocket");

        JSONObject audioParams = new JSONObject();
        audioParams.put("format", "opus");
        audioParams.put("sample_rate", 16000);
        audioParams.put("channels", 1);
        audioParams.put("frame_duration", 60);

        hello.put("audio_params", audioParams);
        return hello;
    }

    public JSONObject createTextMsg(String text) throws JSONException {
        JSONObject jsonMessage = new JSONObject();
        jsonMessage.put("type", "listen");
        jsonMessage.put("state", "detect");
        jsonMessage.put("text", text);
        jsonMessage.put("source", "text");
        return jsonMessage;
    }

    public JSONObject createStartMsg(int sample_rate) throws JSONException {
        JSONObject startMessage = new JSONObject();
        startMessage.put("type", "start");
        startMessage.put("mode", "auto");
        startMessage.put("audio_params", new JSONObject()
                .put("format", "opus")
                .put("sample_rate", sample_rate)
                .put("channels", 1)
                .put("frame_duration", 60));
        return startMessage;
    }

    public JSONObject createListenMsg(String sessionId) throws JSONException {
        JSONObject listenMessage = new JSONObject();
        listenMessage.put("type", "listen");
        listenMessage.put("session_id", sessionId);
        listenMessage.put("state", "start");
        listenMessage.put("mode", "auto");
        return listenMessage;
    }

    public JSONObject createAbortMsg() throws JSONException {
        JSONObject jsonMessage = new JSONObject();
        jsonMessage.put("type", "abort");
        jsonMessage.put("reason", "user_interrupted");
        return jsonMessage;
    }

    public JSONObject createEndMsg() throws JSONException {
        JSONObject endMessage = new JSONObject();
        endMessage.put("type", "end");
        return endMessage;
    }
}
