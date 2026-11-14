package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * JustAudioPlugin
 */
public class JustAudioPlugin implements FlutterPlugin {
    interface LifecycleHost {
        void add(@NonNull EngineLifecycleListener listener);
        void remove(@NonNull EngineLifecycleListener listener);
    }

    private MethodChannel channel;
    private MainMethodCallHandler methodCallHandler;
    private LifecycleHost lifecycleHost;
    private EngineLifecycleListener engineLifecycleListener;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Context applicationContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        @SuppressWarnings("deprecation")
        final FlutterEngine engine = binding.getFlutterEngine();
        attach(applicationContext, messenger, new LifecycleHost() {
            @Override
            public void add(@NonNull EngineLifecycleListener listener) {
                engine.addEngineLifecycleListener(listener);
            }

            @Override
            public void remove(@NonNull EngineLifecycleListener listener) {
                engine.removeEngineLifecycleListener(listener);
            }
        });
    }

    void attach(@NonNull Context applicationContext, @NonNull BinaryMessenger messenger,
            @NonNull LifecycleHost host) {
        methodCallHandler = new MainMethodCallHandler(applicationContext, messenger);

        channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
        channel.setMethodCallHandler(methodCallHandler);
        lifecycleHost = host;
        engineLifecycleListener = new EngineLifecycleListener() {
            @Override
            public void onPreEngineRestart() {
                if (methodCallHandler != null) {
                    methodCallHandler.dispose();
                }
            }

            @Override
            public void onEngineWillDestroy() {
            }
        };
        lifecycleHost.add(engineLifecycleListener);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        detach();
    }

    void detach() {
        if (lifecycleHost != null && engineLifecycleListener != null) {
            lifecycleHost.remove(engineLifecycleListener);
        }
        engineLifecycleListener = null;
        lifecycleHost = null;

        if (methodCallHandler != null) {
            methodCallHandler.dispose();
            methodCallHandler = null;
        }

        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }
}
