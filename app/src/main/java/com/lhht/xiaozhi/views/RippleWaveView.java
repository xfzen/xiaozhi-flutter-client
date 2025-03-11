package com.lhht.xiaozhi.views;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.AttributeSet;
import android.view.View;
import android.view.animation.LinearInterpolator;
import java.util.ArrayList;
import java.util.List;

public class RippleWaveView extends View {
    private Paint paint;
    private List<Circle> circles;
    private float centerX, centerY;
    private boolean isAnimating = false;
    private float maxRadius;
    private float targetAmplitude = 0.5f;
    private float currentAmplitude = 0.5f;
    private ValueAnimator amplitudeAnimator;
    private static final long AMPLITUDE_ANIMATION_DURATION = 200; // 振幅过渡动画时长

    public RippleWaveView(Context context) {
        super(context);
        init();
    }

    public RippleWaveView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        paint = new Paint();
        paint.setAntiAlias(true);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(2);
        circles = new ArrayList<>();
        setupAmplitudeAnimator();
    }

    private void setupAmplitudeAnimator() {
        amplitudeAnimator = ValueAnimator.ofFloat(0f, 1f);
        amplitudeAnimator.setDuration(AMPLITUDE_ANIMATION_DURATION);
        amplitudeAnimator.setInterpolator(new LinearInterpolator());
        amplitudeAnimator.addUpdateListener(animation -> {
            float fraction = animation.getAnimatedFraction();
            currentAmplitude = currentAmplitude + (targetAmplitude - currentAmplitude) * fraction;
            invalidate();
        });
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        centerX = w / 2f;
        centerY = h / 2f;
        maxRadius = Math.min(w, h) / 2f;
        startAnimation();
    }

    private void startAnimation() {
        if (isAnimating) return;
        isAnimating = true;

        ValueAnimator animator = ValueAnimator.ofFloat(0, 1);
        animator.setDuration(3000);
        animator.setRepeatCount(ValueAnimator.INFINITE);
        animator.setInterpolator(new LinearInterpolator());
        animator.addUpdateListener(animation -> {
            updateCircles();
            invalidate();
        });
        animator.start();
    }

    private void updateCircles() {
        // 移除超出范围的圆
        circles.removeIf(circle -> circle.radius > maxRadius);

        // 添加新圆
        if (circles.isEmpty() || circles.get(circles.size() - 1).radius > maxRadius / 4) {
            circles.add(new Circle());
        }

        // 更新现有圆的半径
        for (Circle circle : circles) {
            // 根据当前振幅调整扩散速度
            float speed = 1.5f + currentAmplitude * 2;
            circle.radius += speed;
            circle.alpha = 1 - (circle.radius / maxRadius);
        }
    }

    public void setAmplitude(float amplitude) {
        targetAmplitude = Math.min(1, Math.max(0, amplitude));
        if (amplitudeAnimator.isRunning()) {
            amplitudeAnimator.cancel();
        }
        amplitudeAnimator.start();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        for (Circle circle : circles) {
            paint.setColor(Color.WHITE);
            paint.setAlpha((int) (255 * circle.alpha * (0.3f + currentAmplitude * 0.7f)));
            canvas.drawCircle(centerX, centerY, circle.radius, paint);
        }
    }

    private class Circle {
        float radius = 0;
        float alpha = 1;
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        if (amplitudeAnimator != null) {
            amplitudeAnimator.cancel();
        }
    }
} 