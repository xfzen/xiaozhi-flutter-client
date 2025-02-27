package com.lhht.xiaozhi.adapters;

import android.text.Editable;
import android.text.TextWatcher;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.ImageButton;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import com.lhht.xiaozhi.R;
import java.util.ArrayList;

public class WsUrlAdapter extends RecyclerView.Adapter<WsUrlAdapter.ViewHolder> {
    private final ArrayList<String> wsUrls;
    private final OnUrlDeleteListener listener;

    public interface OnUrlDeleteListener {
        void onDelete(String url);
    }

    public WsUrlAdapter(ArrayList<String> wsUrls, OnUrlDeleteListener listener) {
        this.wsUrls = new ArrayList<>(wsUrls);
        this.listener = listener;
    }

    public void addUrl(String url) {
        wsUrls.add(url);
        notifyItemInserted(wsUrls.size() - 1);
    }

    public void removeUrl(String url) {
        int position = wsUrls.indexOf(url);
        if (position != -1) {
            wsUrls.remove(position);
            notifyItemRemoved(position);
        }
    }

    public ArrayList<String> getUrls() {
        return new ArrayList<>(wsUrls);
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_ws_url, parent, false);
        return new ViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        holder.bind(wsUrls.get(position));
    }

    @Override
    public int getItemCount() {
        return wsUrls.size();
    }

    class ViewHolder extends RecyclerView.ViewHolder {
        private final EditText urlInput;
        private final ImageButton deleteButton;
        private TextWatcher textWatcher;

        ViewHolder(View view) {
            super(view);
            urlInput = view.findViewById(R.id.wsUrlInput);
            deleteButton = view.findViewById(R.id.deleteButton);
        }

        void bind(String url) {
            if (textWatcher != null) {
                urlInput.removeTextChangedListener(textWatcher);
            }

            urlInput.setText(url);

            textWatcher = new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

                @Override
                public void onTextChanged(CharSequence s, int start, int before, int count) {}

                @Override
                public void afterTextChanged(Editable s) {
                    int pos = getAdapterPosition();
                    if (pos != RecyclerView.NO_POSITION) {
                        wsUrls.set(pos, s.toString());
                    }
                }
            };
            urlInput.addTextChangedListener(textWatcher);

            deleteButton.setOnClickListener(v -> {
                int position = getAdapterPosition();
                if (position != RecyclerView.NO_POSITION) {
                    String url1 = wsUrls.get(position);
                    if (listener != null) {
                        listener.onDelete(url1);
                    }
                }
            });
        }
    }
} 