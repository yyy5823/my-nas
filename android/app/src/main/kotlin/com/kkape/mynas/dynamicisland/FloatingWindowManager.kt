package com.kkape.mynas.dynamicisland

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import com.kkape.mynas.R
import kotlin.math.abs

/**
 * 通用悬浮窗灵动岛实现
 * 适用于所有 Android 设备
 */
class FloatingWindowManager(context: Context) : DynamicIslandManager(context) {

    override val type: DynamicIslandType = DynamicIslandType.FLOATING_WINDOW

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private val handler = Handler(Looper.getMainLooper())
    private var autoCollapseRunnable: Runnable? = null

    // 视图引用
    private var collapsedView: View? = null
    private var expandedView: View? = null
    private var coverImageCollapsed: ImageView? = null
    private var coverImageExpanded: ImageView? = null
    private var titleTextCollapsed: TextView? = null
    private var titleTextExpanded: TextView? = null
    private var artistTextExpanded: TextView? = null
    private var playPauseButtonCollapsed: ImageButton? = null
    private var playPauseButtonExpanded: ImageButton? = null
    private var previousButton: ImageButton? = null
    private var nextButton: ImageButton? = null
    private var progressBar: ProgressBar? = null
    private var currentTimeText: TextView? = null
    private var totalTimeText: TextView? = null
    private var closeButton: ImageButton? = null

    // 拖动相关
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    companion object {
        private const val TAG = "FloatingWindowManager"
        private const val AUTO_COLLAPSE_DELAY = 5000L // 5秒后自动收起
        private const val COLLAPSED_WIDTH = 200 // dp
        private const val COLLAPSED_HEIGHT = 48 // dp
        private const val EXPANDED_WIDTH = 320 // dp
        private const val EXPANDED_HEIGHT = 180 // dp
        private const val DRAG_THRESHOLD = 10 // dp
    }

    override fun isSupported(): Boolean {
        // 悬浮窗在所有 Android 6.0+ 设备上都支持
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
    }

    override fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    override fun requestPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            return true
        }
        return false
    }

    override fun initialize() {
        Log.d(TAG, "Initializing FloatingWindowManager")
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun show() {
        if (!hasPermission()) {
            Log.w(TAG, "No overlay permission, cannot show floating window")
            return
        }

        if (floatingView != null) {
            Log.d(TAG, "Floating view already showing")
            return
        }

        handler.post {
            try {
                createFloatingView()
                currentState = DynamicIslandState.COLLAPSED
                Log.d(TAG, "Floating window shown in collapsed state")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show floating window", e)
            }
        }
    }

    override fun hide() {
        handler.post {
            removeFloatingView()
            currentState = DynamicIslandState.HIDDEN
            Log.d(TAG, "Floating window hidden")
        }
    }

    override fun expand() {
        handler.post {
            if (floatingView == null) return@post
            animateToExpanded()
            currentState = DynamicIslandState.EXPANDED
            callback?.onExpand()
            scheduleAutoCollapse()
            Log.d(TAG, "Floating window expanded")
        }
    }

    override fun collapse() {
        handler.post {
            if (floatingView == null) return@post
            animateToCollapsed()
            currentState = DynamicIslandState.COLLAPSED
            cancelAutoCollapse()
            Log.d(TAG, "Floating window collapsed")
        }
    }

    override fun updateData(data: DynamicIslandData) {
        currentData = data
        handler.post {
            updateViewData()
        }
    }

    override fun release() {
        handler.post {
            cancelAutoCollapse()
            removeFloatingView()
            windowManager = null
            Log.d(TAG, "FloatingWindowManager released")
        }
    }

    private fun createFloatingView() {
        val inflater = LayoutInflater.from(context)
        floatingView = inflater.inflate(R.layout.dynamic_island_floating, null)

        // 绑定视图
        bindViews()
        setupClickListeners()
        setupTouchListener()

        // 设置布局参数
        val density = context.resources.displayMetrics.density
        layoutParams = WindowManager.LayoutParams(
            (COLLAPSED_WIDTH * density).toInt(),
            (COLLAPSED_HEIGHT * density).toInt(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (40 * density).toInt() // 距离顶部 40dp
        }

        // 添加到窗口
        windowManager?.addView(floatingView, layoutParams)

        // 初始化为收起状态
        collapsedView?.visibility = View.VISIBLE
        expandedView?.visibility = View.GONE

        // 更新数据
        updateViewData()
    }

    private fun bindViews() {
        floatingView?.let { view ->
            collapsedView = view.findViewById(R.id.layout_collapsed)
            expandedView = view.findViewById(R.id.layout_expanded)
            coverImageCollapsed = view.findViewById(R.id.image_cover_collapsed)
            coverImageExpanded = view.findViewById(R.id.image_cover_expanded)
            titleTextCollapsed = view.findViewById(R.id.text_title_collapsed)
            titleTextExpanded = view.findViewById(R.id.text_title_expanded)
            artistTextExpanded = view.findViewById(R.id.text_artist_expanded)
            playPauseButtonCollapsed = view.findViewById(R.id.btn_play_pause_collapsed)
            playPauseButtonExpanded = view.findViewById(R.id.btn_play_pause_expanded)
            previousButton = view.findViewById(R.id.btn_previous)
            nextButton = view.findViewById(R.id.btn_next)
            progressBar = view.findViewById(R.id.progress_bar)
            currentTimeText = view.findViewById(R.id.text_current_time)
            totalTimeText = view.findViewById(R.id.text_total_time)
            closeButton = view.findViewById(R.id.btn_close)
        }
    }

    private fun setupClickListeners() {
        // 收起状态点击展开
        collapsedView?.setOnClickListener {
            if (!isDragging) {
                expand()
            }
        }

        // 播放/暂停按钮
        playPauseButtonCollapsed?.setOnClickListener {
            callback?.onPlayPause()
        }
        playPauseButtonExpanded?.setOnClickListener {
            callback?.onPlayPause()
        }

        // 上一首/下一首
        previousButton?.setOnClickListener {
            callback?.onPrevious()
        }
        nextButton?.setOnClickListener {
            callback?.onNext()
        }

        // 关闭按钮
        closeButton?.setOnClickListener {
            callback?.onDismiss()
            hide()
        }

        // 展开状态点击收起
        expandedView?.setOnClickListener {
            collapse()
        }
    }

    private fun setupTouchListener() {
        val density = context.resources.displayMetrics.density
        val dragThreshold = DRAG_THRESHOLD * density

        floatingView?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams?.x ?: 0
                    initialY = layoutParams?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - initialTouchX
                    val deltaY = event.rawY - initialTouchY

                    if (abs(deltaX) > dragThreshold || abs(deltaY) > dragThreshold) {
                        isDragging = true
                        layoutParams?.x = initialX + deltaX.toInt()
                        layoutParams?.y = initialY + deltaY.toInt()
                        windowManager?.updateViewLayout(floatingView, layoutParams)
                    }
                    isDragging
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        snapToEdge()
                    }
                    isDragging
                }
                else -> false
            }
        }
    }

    private fun snapToEdge() {
        val displayMetrics = context.resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val currentX = layoutParams?.x ?: 0

        // 计算到左右边缘的距离
        val distanceToLeft = abs(currentX)
        val distanceToRight = abs(screenWidth - currentX - (floatingView?.width ?: 0))

        val targetX = if (distanceToLeft < distanceToRight) 0 else screenWidth - (floatingView?.width ?: 0)

        ValueAnimator.ofInt(currentX, targetX).apply {
            duration = 200
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                layoutParams?.x = animation.animatedValue as Int
                windowManager?.updateViewLayout(floatingView, layoutParams)
            }
            start()
        }
    }

    private fun animateToExpanded() {
        val density = context.resources.displayMetrics.density
        val targetWidth = (EXPANDED_WIDTH * density).toInt()
        val targetHeight = (EXPANDED_HEIGHT * density).toInt()

        val currentWidth = floatingView?.width ?: (COLLAPSED_WIDTH * density).toInt()
        val currentHeight = floatingView?.height ?: (COLLAPSED_HEIGHT * density).toInt()

        collapsedView?.visibility = View.GONE
        expandedView?.visibility = View.VISIBLE
        expandedView?.alpha = 0f

        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 300
            interpolator = OvershootInterpolator(1.2f)
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                layoutParams?.width = (currentWidth + (targetWidth - currentWidth) * progress).toInt()
                layoutParams?.height = (currentHeight + (targetHeight - currentHeight) * progress).toInt()
                windowManager?.updateViewLayout(floatingView, layoutParams)
                expandedView?.alpha = progress
            }
            start()
        }
    }

    private fun animateToCollapsed() {
        val density = context.resources.displayMetrics.density
        val targetWidth = (COLLAPSED_WIDTH * density).toInt()
        val targetHeight = (COLLAPSED_HEIGHT * density).toInt()

        val currentWidth = floatingView?.width ?: (EXPANDED_WIDTH * density).toInt()
        val currentHeight = floatingView?.height ?: (EXPANDED_HEIGHT * density).toInt()

        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 250
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                layoutParams?.width = (currentWidth + (targetWidth - currentWidth) * progress).toInt()
                layoutParams?.height = (currentHeight + (targetHeight - currentHeight) * progress).toInt()
                windowManager?.updateViewLayout(floatingView, layoutParams)
                expandedView?.alpha = 1f - progress
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    collapsedView?.visibility = View.VISIBLE
                    expandedView?.visibility = View.GONE
                }
            })
            start()
        }
    }

    private fun updateViewData() {
        if (floatingView == null) return

        // 封面图片
        if (currentData.coverBitmap != null) {
            coverImageCollapsed?.setImageBitmap(currentData.coverBitmap)
            coverImageExpanded?.setImageBitmap(currentData.coverBitmap)
        } else {
            coverImageCollapsed?.setImageResource(R.drawable.ic_music_note)
            coverImageExpanded?.setImageResource(R.drawable.ic_music_note)
        }

        // 标题
        titleTextCollapsed?.text = currentData.title ?: "未知歌曲"
        titleTextExpanded?.text = currentData.title ?: "未知歌曲"

        // 艺术家
        artistTextExpanded?.text = currentData.artist ?: "未知艺术家"

        // 播放/暂停按钮
        val playPauseIcon = if (currentData.isPlaying) R.drawable.ic_pause else R.drawable.ic_play
        playPauseButtonCollapsed?.setImageResource(playPauseIcon)
        playPauseButtonExpanded?.setImageResource(playPauseIcon)

        // 进度条
        progressBar?.progress = currentData.progressPercent

        // 时间
        currentTimeText?.text = currentData.currentTimeFormatted
        totalTimeText?.text = currentData.totalTimeFormatted
    }

    private fun removeFloatingView() {
        floatingView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to remove floating view", e)
            }
        }
        floatingView = null
    }

    private fun scheduleAutoCollapse() {
        cancelAutoCollapse()
        autoCollapseRunnable = Runnable {
            if (currentState == DynamicIslandState.EXPANDED) {
                collapse()
            }
        }
        handler.postDelayed(autoCollapseRunnable!!, AUTO_COLLAPSE_DELAY)
    }

    private fun cancelAutoCollapse() {
        autoCollapseRunnable?.let { handler.removeCallbacks(it) }
        autoCollapseRunnable = null
    }
}
