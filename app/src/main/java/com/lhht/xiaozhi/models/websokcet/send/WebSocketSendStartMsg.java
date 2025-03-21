package com.lhht.xiaozhi.models.websokcet.send;

import com.lhht.xiaozhi.models.websokcet.send.core.WebSocketSendMsg;
import com.lhht.xiaozhi.models.websokcet.send.core.WebSocketSendMsgDataFactory;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * @author chenguijian
 * @since 2025/3/21
 */
class WebSocketSendStartMsg extends WebSocketSendMsg {
    private final JSONObject data;

    public WebSocketSendStartMsg(int sample_rate) throws JSONException {
        this.data = WebSocketSendMsgDataFactory.getInstance().createStartMsg(sample_rate);
    }

    @Override
    public String toJsonString() {
        return data.toString();
    }
}
