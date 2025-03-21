package com.lhht.xiaozhi.models.websokcet.send;

import com.lhht.xiaozhi.models.websokcet.send.core.WebSocketSendMsg;
import com.lhht.xiaozhi.models.websokcet.send.core.WebSocketSendMsgDataFactory;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * @author chenguijian
 * @since 2025/3/21
 */
class WebSocketSendListenMsg extends WebSocketSendMsg {

    private final JSONObject data;

    public WebSocketSendListenMsg(String sessionId) throws JSONException {
        this.data = WebSocketSendMsgDataFactory.getInstance().createListenMsg(sessionId);
    }

    @Override
    public String toJsonString() {
        return data.toString();
    }
}