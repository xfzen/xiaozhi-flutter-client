package com.lhht.xiaozhi.models.websokcet.send;

import com.lhht.xiaozhi.models.websokcet.send.core.WebSocketSendMsg;

import org.json.JSONException;

/**
 * @author chenguijian
 * @since 2025/3/21
 */
public class WebSocketSendMsgFactory {

    private static class WebSocketSendMsgFactoryHolder {
        private static final WebSocketSendMsgFactory INSTANCE = new WebSocketSendMsgFactory();
    }

    private WebSocketSendMsgFactory() {

    }

    public static WebSocketSendMsgFactory getInstance() {
        return WebSocketSendMsgFactory.WebSocketSendMsgFactoryHolder.INSTANCE;
    }

    public WebSocketSendMsg createHelloMsg() throws JSONException {
        return new WebSocketSendHelloMsg();
    }

    public WebSocketSendMsg createTextMsg(String text) throws JSONException {
        return new WebSocketSendTextMsg(text);
    }

    public WebSocketSendMsg createStartMsg(int sample_rate) throws JSONException {
        return new WebSocketSendStartMsg(sample_rate);
    }

    public WebSocketSendMsg createListenMsg(String sessionId) throws JSONException {
        return new WebSocketSendListenMsg(sessionId);
    }

    public WebSocketSendMsg createAbortMsg() throws JSONException {
        return new WebSocketSendAbortMsg();
    }

    public WebSocketSendMsg createEndMsg() throws JSONException {
        return new WebSocketSendEndMsg();
    }

}
