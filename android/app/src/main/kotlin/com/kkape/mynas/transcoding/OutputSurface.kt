package com.kkape.mynas.transcoding

import android.graphics.SurfaceTexture
import android.opengl.*
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * OutputSurface 用于接收解码器输出并通过 OpenGL ES 进行缩放
 *
 * 解码器输出 -> SurfaceTexture -> OpenGL ES 渲染 -> 编码器 InputSurface
 */
class OutputSurface(
    private val width: Int,
    private val height: Int
) : SurfaceTexture.OnFrameAvailableListener {

    companion object {
        private const val TAG = "OutputSurface"

        // OpenGL ES 着色器
        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTextureCoord;
            varying vec2 vTextureCoord;
            void main() {
                gl_Position = aPosition;
                vTextureCoord = aTextureCoord.xy;
            }
        """

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTextureCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vTextureCoord);
            }
        """

        // 顶点坐标（覆盖整个屏幕）
        private val VERTICES = floatArrayOf(
            -1.0f, -1.0f,  // 左下
             1.0f, -1.0f,  // 右下
            -1.0f,  1.0f,  // 左上
             1.0f,  1.0f,  // 右上
        )

        // 纹理坐标（正常方向）
        private val TEXTURE_COORDS = floatArrayOf(
            0.0f, 0.0f,
            1.0f, 0.0f,
            0.0f, 1.0f,
            1.0f, 1.0f,
        )
    }

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var eglConfig: EGLConfig? = null

    private var surfaceTexture: SurfaceTexture? = null
    private var textureId = -1

    private var program = -1
    private var positionHandle = -1
    private var textureCoordsHandle = -1

    private var vertexBuffer: FloatBuffer
    private var textureCoordsBuffer: FloatBuffer

    private val frameSyncObject = Object()
    private var frameAvailable = false

    val surface: Surface
        get() = Surface(surfaceTexture)

    init {
        // 创建顶点缓冲
        vertexBuffer = ByteBuffer.allocateDirect(VERTICES.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .put(VERTICES)
        vertexBuffer.position(0)

        textureCoordsBuffer = ByteBuffer.allocateDirect(TEXTURE_COORDS.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .put(TEXTURE_COORDS)
        textureCoordsBuffer.position(0)

        setupEGL()
        setupGL()
        setupSurfaceTexture()
    }

    private fun setupEGL() {
        // 获取 EGL Display
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
            throw RuntimeException("Unable to get EGL display")
        }

        // 初始化 EGL
        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw RuntimeException("Unable to initialize EGL")
        }

        // 配置 EGL
        val configAttribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE
        )

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)) {
            throw RuntimeException("Unable to choose EGL config")
        }
        eglConfig = configs[0]

        // 创建 EGL Context
        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )
        eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT,
            contextAttribs, 0)
        if (eglContext == EGL14.EGL_NO_CONTEXT) {
            throw RuntimeException("Unable to create EGL context")
        }

        // 创建 PBuffer Surface
        val surfaceAttribs = intArrayOf(
            EGL14.EGL_WIDTH, width,
            EGL14.EGL_HEIGHT, height,
            EGL14.EGL_NONE
        )
        eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, surfaceAttribs, 0)
        if (eglSurface == EGL14.EGL_NO_SURFACE) {
            throw RuntimeException("Unable to create EGL surface")
        }

        // 绑定 Context
        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("Unable to make EGL context current")
        }
    }

    private fun setupGL() {
        // 创建纹理
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        // 编译着色器
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)

        // 创建程序
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertexShader)
        GLES20.glAttachShader(program, fragmentShader)
        GLES20.glLinkProgram(program)

        val linkStatus = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
        if (linkStatus[0] == 0) {
            val error = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw RuntimeException("Program link failed: $error")
        }

        // 获取属性位置
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        textureCoordsHandle = GLES20.glGetAttribLocation(program, "aTextureCoord")
    }

    private fun loadShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val compileStatus = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0)
        if (compileStatus[0] == 0) {
            val error = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("Shader compile failed: $error")
        }

        return shader
    }

    private fun setupSurfaceTexture() {
        surfaceTexture = SurfaceTexture(textureId).apply {
            setOnFrameAvailableListener(this@OutputSurface)
            setDefaultBufferSize(width, height)
        }
    }

    override fun onFrameAvailable(surfaceTexture: SurfaceTexture) {
        synchronized(frameSyncObject) {
            if (frameAvailable) {
                Log.w(TAG, "Frame dropped - previous frame not consumed")
            }
            frameAvailable = true
            frameSyncObject.notifyAll()
        }
    }

    /**
     * 等待新帧可用
     */
    fun awaitNewImage() {
        synchronized(frameSyncObject) {
            while (!frameAvailable) {
                try {
                    // 等待最多 5 秒
                    frameSyncObject.wait(5000)
                    if (!frameAvailable) {
                        throw RuntimeException("Timeout waiting for frame")
                    }
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw RuntimeException("Interrupted waiting for frame", e)
                }
            }
            frameAvailable = false
        }

        // 更新纹理
        surfaceTexture?.updateTexImage()
    }

    /**
     * 绘制当前帧
     */
    fun drawImage() {
        GLES20.glViewport(0, 0, width, height)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(program)

        // 设置顶点属性
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)

        GLES20.glEnableVertexAttribArray(textureCoordsHandle)
        GLES20.glVertexAttribPointer(textureCoordsHandle, 2, GLES20.GL_FLOAT, false, 0, textureCoordsBuffer)

        // 绑定纹理
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

        // 绘制
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        // 清理
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(textureCoordsHandle)
    }

    /**
     * 渲染到另一个 Surface（编码器的 InputSurface）
     */
    fun renderToSurface(targetSurface: Surface, presentationTimeNs: Long) {
        // 创建目标 EGL Surface
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        val targetEglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay, eglConfig, targetSurface, surfaceAttribs, 0
        )

        if (targetEglSurface == EGL14.EGL_NO_SURFACE) {
            Log.e(TAG, "Failed to create target EGL surface")
            return
        }

        try {
            // 绑定目标 Surface
            EGL14.eglMakeCurrent(eglDisplay, targetEglSurface, targetEglSurface, eglContext)

            // 绘制
            drawImage()

            // 设置时间戳并交换缓冲
            EGLExt.eglPresentationTimeANDROID(eglDisplay, targetEglSurface, presentationTimeNs * 1000)
            EGL14.eglSwapBuffers(eglDisplay, targetEglSurface)
        } finally {
            // 恢复原来的 Surface
            EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
            EGL14.eglDestroySurface(eglDisplay, targetEglSurface)
        }
    }

    /**
     * 释放资源
     */
    fun release() {
        if (program >= 0) {
            GLES20.glDeleteProgram(program)
            program = -1
        }

        if (textureId >= 0) {
            GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
            textureId = -1
        }

        surfaceTexture?.release()
        surfaceTexture = null

        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            eglSurface = EGL14.EGL_NO_SURFACE
        }

        if (eglContext != EGL14.EGL_NO_CONTEXT) {
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            eglContext = EGL14.EGL_NO_CONTEXT
        }

        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglTerminate(eglDisplay)
            eglDisplay = EGL14.EGL_NO_DISPLAY
        }
    }
}
