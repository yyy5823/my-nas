package com.kkape.mynas.dynamicisland

import android.content.Context
import android.util.Log

/**
 * 灵动岛工厂
 * 根据设备类型选择合适的灵动岛实现
 */
object DynamicIslandFactory {

    private const val TAG = "DynamicIslandFactory"

    private var instance: DynamicIslandManager? = null

    /**
     * 获取灵动岛管理器单例
     */
    fun getInstance(context: Context): DynamicIslandManager {
        if (instance == null) {
            instance = createManager(context.applicationContext)
        }
        return instance!!
    }

    /**
     * 创建灵动岛管理器
     * 优先级：华为 Live View Kit > 通用悬浮窗
     */
    private fun createManager(context: Context): DynamicIslandManager {
        Log.d(TAG, "Creating DynamicIslandManager...")

        // 1. 尝试华为 Live View Kit
        if (HuaweiLiveViewManager.isHuaweiDevice()) {
            Log.d(TAG, "Huawei device detected, checking Live View Kit...")
            val huaweiManager = HuaweiLiveViewManager(context)
            if (huaweiManager.isSupported()) {
                Log.d(TAG, "Using HuaweiLiveViewManager")
                return huaweiManager
            }
            Log.d(TAG, "Live View Kit not supported, falling back to floating window")
        }

        // 2. 使用通用悬浮窗
        val floatingManager = FloatingWindowManager(context)
        if (floatingManager.isSupported()) {
            Log.d(TAG, "Using FloatingWindowManager")
            return floatingManager
        }

        // 3. 不支持任何实现
        Log.w(TAG, "No Dynamic Island implementation supported, using NoOpManager")
        return NoOpDynamicIslandManager(context)
    }

    /**
     * 释放单例
     */
    fun release() {
        instance?.release()
        instance = null
        Log.d(TAG, "DynamicIslandFactory released")
    }

    /**
     * 获取设备支持的灵动岛类型
     */
    fun getSupportedType(context: Context): DynamicIslandType {
        return getInstance(context).type
    }

    /**
     * 检查设备是否支持灵动岛
     */
    fun isSupported(context: Context): Boolean {
        return getInstance(context).type != DynamicIslandType.NOT_SUPPORTED
    }
}

/**
 * 空实现，用于不支持灵动岛的设备
 */
class NoOpDynamicIslandManager(context: Context) : DynamicIslandManager(context) {
    override val type: DynamicIslandType = DynamicIslandType.NOT_SUPPORTED
    override fun isSupported(): Boolean = false
    override fun hasPermission(): Boolean = false
    override fun requestPermission(): Boolean = false
    override fun initialize() {}
    override fun show() {}
    override fun hide() {}
    override fun expand() {}
    override fun collapse() {}
    override fun updateData(data: DynamicIslandData) {}
    override fun release() {}
}
