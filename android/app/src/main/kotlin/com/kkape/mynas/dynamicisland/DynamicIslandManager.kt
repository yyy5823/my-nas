package com.kkape.mynas.dynamicisland

import android.content.Context

/**
 * 灵动岛管理器抽象接口
 * 定义统一的灵动岛操作接口，不同厂商实现各自的子类
 */
abstract class DynamicIslandManager(protected val context: Context) {

    var callback: DynamicIslandCallback? = null
    protected var currentState: DynamicIslandState = DynamicIslandState.HIDDEN
    protected var currentData: DynamicIslandData = DynamicIslandData.EMPTY

    /**
     * 获取灵动岛类型
     */
    abstract val type: DynamicIslandType

    /**
     * 检查当前设备是否支持此实现
     */
    abstract fun isSupported(): Boolean

    /**
     * 检查是否有必要的权限
     */
    abstract fun hasPermission(): Boolean

    /**
     * 请求必要的权限
     * @return true 如果权限请求已发起
     */
    abstract fun requestPermission(): Boolean

    /**
     * 初始化灵动岛
     * 在使用前必须调用此方法
     */
    abstract fun initialize()

    /**
     * 显示灵动岛（收起状态）
     */
    abstract fun show()

    /**
     * 隐藏灵动岛
     */
    abstract fun hide()

    /**
     * 展开灵动岛
     */
    abstract fun expand()

    /**
     * 收起灵动岛
     */
    abstract fun collapse()

    /**
     * 更新媒体数据
     */
    abstract fun updateData(data: DynamicIslandData)

    /**
     * 释放资源
     */
    abstract fun release()

    
    /**
     * 设置回调 - 直接通过属性赋值实现
     */
    open fun setCallbackHandler(newCallback: DynamicIslandCallback?) {
        this.callback = newCallback
    }

    /**
     * 获取当前状态
     */
    fun getState(): DynamicIslandState = currentState

    /**
     * 获取当前数据
     */
    fun getData(): DynamicIslandData = currentData

    companion object {
        private const val TAG = "DynamicIslandManager"
    }
}
