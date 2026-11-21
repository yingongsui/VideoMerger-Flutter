package com.flutter.videomerger // 确保包名与你的 namespace 一致

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.baseflow.permissionhandler.PermissionHandlerPlugin // 导入插件

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 💡 显式注册 permission_handler 插件
        flutterEngine.plugins.add(PermissionHandlerPlugin())
    }
}