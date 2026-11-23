package com.pulsr.music
 
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.app.SearchManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.audio.generic.AbstractTag
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.flac.FlacTag
import org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag
import java.io.File
import java.io.FileInputStream
 
class MainActivity : AudioServiceActivity() {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (UsbExclusivePlugin.isHardwareVolumeActive()) {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    val stepUp = keyCode == KeyEvent.KEYCODE_VOLUME_UP
                    UsbExclusivePlugin.stepHardwareVolume(stepUp)
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private val LYRICS_CHANNEL = "com.pulsr.music/lyrics"
    private val FILE_OPENER_CHANNEL = "com.pulsr.music/file_opener"
    private val ASSISTANT_CHANNEL = "com.pulsr.music/assistant"
    private val pendingAudioUris = ArrayDeque<String>()
    private val pendingAssistantExtras = ArrayDeque<Map<String, String>>()
    companion object {
        private const val MAX_PENDING_AUDIO_URIS = 32
        private const val MAX_PENDING_ASSISTANT_EXTRAS = 8

        /**
         * Set once the Dart assistant service answers `assistantReady`.
         *
         * Process-wide so re-creating the Activity does not downgrade warm
         * starts to the query-only legacy path while the Dart handler is still
         * installed.
         */
        @Volatile private var assistantReady = false

        // Tracks which MainActivity currently owns the Activity-scoped channels on
        // each cached FlutterEngine so a finishing Activity's cleanUpFlutterEngine
        // cannot strip handlers installed by its replacement (M-12).
        private val activeActivityByEngine = java.util.IdentityHashMap<FlutterEngine, MainActivity>()
    }

    /**
     * Search-intent extras forwarded to the Dart assistant service.
     *
     * The canonical uppercase keys match `parseSearchExtras` on the Dart side;
     * the aliases cover both the platform constants (SearchManager.QUERY,
     * MediaStore.EXTRA_MEDIA_*) and lower-case senders.
     */
    private val assistantExtraAliases = listOf(
        "QUERY" to listOf(SearchManager.QUERY, SearchManager.USER_QUERY, "QUERY"),
        "PLAYLIST" to listOf("PLAYLIST", "playlist"),
        "ALBUM" to listOf(MediaStore.EXTRA_MEDIA_ALBUM, "ALBUM", "album"),
        "ARTIST" to listOf(MediaStore.EXTRA_MEDIA_ARTIST, "ARTIST", "artist"),
        "GENRE" to listOf("GENRE", "genre"),
        "SONG" to listOf(MediaStore.EXTRA_MEDIA_TITLE, "SONG", "song"),
        "TITLE" to listOf("TITLE", "title"),
        "MIME_TYPE" to listOf("MIME_TYPE", "mime_type")
    )

    private fun addPendingAudioUri(uri: String) {
        synchronized(pendingAudioUris) {
            while (pendingAudioUris.size >= MAX_PENDING_AUDIO_URIS) {
                pendingAudioUris.removeFirstOrNull()
            }
            pendingAudioUris.addLast(uri)
        }
    }

    /**
     * Queues assistant extras until the Dart handler is bound (cold start).
     */
    private fun queueAssistantExtras(extras: Map<String, String>) {
        if (extras.isEmpty()) return
        synchronized(pendingAssistantExtras) {
            while (pendingAssistantExtras.size >= MAX_PENDING_ASSISTANT_EXTRAS) {
                pendingAssistantExtras.removeFirstOrNull()
            }
            pendingAssistantExtras.addLast(extras)
        }
    }

    /** Reads the media-search extras the Dart resolver understands. */
    private fun readAssistantExtras(intent: Intent): Map<String, String> {
        val extras = LinkedHashMap<String, String>()
        for ((canonical, aliases) in assistantExtraAliases) {
            for (key in aliases) {
                val value = intent.getStringExtra(key)
                if (!value.isNullOrBlank()) {
                    extras[canonical] = value
                    break
                }
            }
        }
        intent.type?.takeIf { it.isNotBlank() }?.let { extras["MIME_TYPE"] = it }
        return extras
    }

    /**
     * Forwards one ACTION_SEARCH intent to Dart.
     *
     * ACTION_SEARCH had no legacy handler, so its extras are queued on cold
     * start and flushed when the assistant channel binds.
     */
    private fun forwardSearchIntent(intent: Intent, fromColdStart: Boolean): Boolean {
        val extras = readAssistantExtras(intent)
        if (extras.isEmpty()) return false
        val channel = assistantChannel
        if (!fromColdStart && channel != null) {
            channel.invokeMethod("onSearchQuery", extras)
        } else {
            queueAssistantExtras(extras)
        }
        return true
    }

    private fun flushPendingAssistantExtras(channel: MethodChannel) {
        val pending = synchronized(pendingAssistantExtras) {
            val copy = pendingAssistantExtras.toList()
            pendingAssistantExtras.clear()
            copy
        }
        for (extras in pending) {
            channel.invokeMethod("onSearchQuery", extras)
        }
    }
    private var fileOpenerChannel: MethodChannel? = null
    private var assistantChannel: MethodChannel? = null
    private var lyricsChannel: MethodChannel? = null
    private var purityChannel: MethodChannel? = null
    private var batteryChannel: MethodChannel? = null
    private var updaterChannel: MethodChannel? = null
    private var playbackTileChannel: MethodChannel? = null
    private var boundFlutterEngine: FlutterEngine? = null
    @Volatile private var activityChannelsBound = false
    private val lyricsExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
    private var mediaReceiver: android.content.BroadcastReceiver? = null
 
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val attrs = window.attributes
            attrs.layoutInDisplayCutoutMode =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                } else {
                    android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            window.attributes = attrs
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        applyHighRefreshRateDisplayMode()
        registerStorageReceiver()
        handleAudioIntent(intent, fromColdStart = true)
    }
 
    override fun onResume() {
        super.onResume()
        applyHighRefreshRateDisplayMode()
    }

    /**
     * Requests the highest available display refresh rate (e.g. 90Hz / 120Hz / 144Hz)
     * matching the active physical resolution unless OS Battery Saver is active.
     */
    private fun applyHighRefreshRateDisplayMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager?.isPowerSaveMode == true) return

            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val currentMode = currentDisplay.mode ?: return
            val bestMode = currentDisplay.supportedModes
                .filter {
                    it.physicalWidth == currentMode.physicalWidth &&
                        it.physicalHeight == currentMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return

            if (bestMode.modeId != currentMode.modeId || bestMode.refreshRate > 60.5f) {
                val params = window.attributes
                if (params.preferredDisplayModeId != bestMode.modeId) {
                    params.preferredDisplayModeId = bestMode.modeId
                    params.preferredRefreshRate = bestMode.refreshRate
                    window.attributes = params
                }
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "High refresh rate negotiation skipped: ${e.message}")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAudioIntent(intent, fromColdStart = false)
    }

    override fun onDestroy() {
        synchronized(pendingAudioUris) {
            pendingAudioUris.clear()
        }
        try {
            // Never block the main thread waiting for a tag read; the tag
            // library can sit in disk I/O for seconds on a slow provider.
            lyricsExecutor.shutdownNow()
        } catch (e: Exception) {
            Log.w("MainActivity", "Error shutting down lyrics executor: ${e.message}")
        }
        try {
            mediaReceiver?.let { unregisterReceiver(it) }
            mediaReceiver = null
        } catch (_: Exception) {}
        super.onDestroy()
    }
 
    private fun isAudioIntent(intent: Intent, uri: Uri): Boolean {
        return AudioIntentClassifier.isAudioIntent(intent, uri)
    }

    private fun isProxyText(text: String): Boolean {
        return AudioIntentClassifier.isProxyText(text)
    }

    private fun isYouTubeUrl(text: String): Boolean {
        return AudioIntentClassifier.isYouTubeUrl(text)
    }

    private fun isSafeUri(uri: Uri): Boolean {
        // The current user-facing roots; kept here so the classifier stays pure.
        @Suppress("DEPRECATION")
        val extStorage = android.os.Environment.getExternalStorageDirectory()?.path
        val roots = listOfNotNull(
            extStorage,
            getExternalFilesDir(null)?.path,
            filesDir?.path,
            cacheDir?.path,
            "/storage",
            "/sdcard",
        )
        val safe = AudioIntentClassifier.isSafeUri(uri, roots)
        if (!safe) {
            Log.w("MainActivity", "Rejected URI with unsafe scheme or path: $uri")
        }
        return safe
    }

    internal fun canReadDirectly(fileUri: Uri): Boolean {
        val path = fileUri.path ?: return false
        val file = File(path)
        return try {
            file.exists() && file.canRead() && FileInputStream(file).use { true }
        } catch (_: Exception) {
            false
        }
    }

    internal fun resolveFileUriToContentUri(fileUri: Uri): Uri? {
        return AudioTempFiles.resolveMediaStoreContentUri(this, fileUri)
    }

    internal fun resolvePlayableAudioUri(uri: Uri): Uri {
        if (uri.scheme?.equals("file", ignoreCase = true) != true) {
            return uri
        }
        if (canReadDirectly(uri)) {
            return uri
        }

        // Resolves file:// URI that cannot be read directly due to scoped storage/permissions (Android 13-17).
        // 1. Try resolving to a content URI via MediaStore query (MediaStore.Audio.Media.DATA)
        val contentUri = resolveFileUriToContentUri(uri)
        if (contentUri != null) {
            Log.d("MainActivity", "Resolved unreadable file URI $uri to content URI $contentUri")
            return contentUri
        }

        // 2. Fall back to copying using AudioTempFiles.copyToTempFile to app cache
        return try {
            val tempFile = AudioTempFiles.copyToTempFile(this, uri, "audio_intent_")
            val cachedUri = Uri.fromFile(tempFile)
            Log.d("MainActivity", "Copied unreadable file URI $uri to app cache $cachedUri")
            cachedUri
        } catch (e: Exception) {
            Log.w("MainActivity", "Failed to resolve or copy audio file URI $uri: ${e.message}", e)
            uri
        }
    }

    private fun handleAudioIntent(intent: Intent?, fromColdStart: Boolean) {
        // Assistant / voice-search entry point: bring the app forward so the
        // Dart layer can resume or start playback. Previously dropped.
        if (intent?.action == "android.media.action.MEDIA_PLAY_FROM_SEARCH") {
            val q = intent.getStringExtra(SearchManager.QUERY)
            val channel = assistantChannel
            // Warm start (or an Activity recreated while Dart is alive): the
            // full extras map (ALBUM / ARTIST / SONG ...) goes to the assistant
            // service instead of only the free-text query. Deduplication lives
            // in AssistantIntentService.
            if (assistantReady) {
                if (!fromColdStart && channel != null) {
                    channel.invokeMethod("onSearchQuery", readAssistantExtras(intent))
                } else {
                    // Channel not bound yet; the bind-time probe or handshake
                    // flushes the queue.
                    queueAssistantExtras(readAssistantExtras(intent))
                }
                return
            }
            // True process cold start: keep the existing query path so voice
            // search always works even if the Dart service is absent.
            if (fromColdStart || fileOpenerChannel == null) {
                addPendingAudioUri("pulsr://voice-search?query=${Uri.encode(q ?: "")}")
            } else {
                fileOpenerChannel?.invokeMethod("onVoiceSearch", q ?: "")
            }
            return
        }
        if (intent?.action == Intent.ACTION_SEARCH) {
            forwardSearchIntent(intent, fromColdStart)
            return
        }
        if (intent?.action != Intent.ACTION_VIEW &&
            intent?.action != Intent.ACTION_SEND &&
            intent?.action != Intent.ACTION_SEND_MULTIPLE
        ) return
        // Multi-share (EXTRA_STREAM as list) previously dropped all but one.
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            try {
                val rawList: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                val list = rawList?.filter { u ->
                    if (!isSafeUri(u)) return@filter false
                    val mime = if (u.scheme?.equals("content", ignoreCase = true) == true) {
                        runCatching { contentResolver.getType(u) }.getOrNull() ?: intent.type
                    } else {
                        intent.type
                    }
                    AudioIntentClassifier.isAudioIntentParts(
                        action = intent.action,
                        scheme = u.scheme,
                        path = u.path,
                        host = u.host,
                        mimeType = mime,
                        textExtra = null,
                    )
                }?.map { u ->
                    if (u.scheme?.equals("content", ignoreCase = true) == true) {
                        try {
                            val flags = intent.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            if (flags != 0) {
                                contentResolver.takePersistableUriPermission(u, flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                        } catch (e: Exception) {
                            Log.d("MainActivity", "Persistable URI grant not supported or failed for $u: ${e.message}")
                        }
                    }
                    resolvePlayableAudioUri(u)
                }
                if (!list.isNullOrEmpty()) {
                    if (fromColdStart || fileOpenerChannel == null) {
                        for (u in list) addPendingAudioUri(u.toString())
                    } else {
                        // Warm start: emit the first URI once and park the rest
                        // for getInitialAudioUri. Enqueueing the first too made
                        // Dart open it a second time when it drained the queue.
                        fileOpenerChannel?.invokeMethod("onAudioFileOpened", list.first().toString())
                        for (u in list.drop(1)) addPendingAudioUri(u.toString())
                    }
                    return
                }
            } catch (_: Exception) {}
        }
        val textExtra = intent.getStringExtra(Intent.EXTRA_TEXT)
        val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val uri = intent.data ?: streamUri ?: (if (!textExtra.isNullOrEmpty() && (isYouTubeUrl(textExtra) || isProxyText(textExtra))) Uri.parse(textExtra) else null) ?: return
        if (!isSafeUri(uri)) {
            Log.w("MainActivity", "Ignoring unsafe URI: $uri")
            return
        }
        if (!isAudioIntent(intent, uri)) return

        if (uri.scheme?.equals("content", ignoreCase = true) == true) {
            try {
                val flags = intent.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (flags != 0) {
                    contentResolver.takePersistableUriPermission(uri, flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } catch (e: Exception) {
                Log.d("MainActivity", "Persistable URI grant not supported or failed for $uri: ${e.message}")
            }
        }

        val playableUri = resolvePlayableAudioUri(uri)
        val uriStr = playableUri.toString()
        if (fromColdStart || fileOpenerChannel == null) {
            addPendingAudioUri(uriStr)
        } else {
            fileOpenerChannel?.invokeMethod("onAudioFileOpened", uriStr)
        }
    }
 

 
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // audio_service re-attaches the same cached engine to every Activity, so
        // this method runs more than once per process. Engine-scoped plugins are
        // created once per engine; only Activity-scoped channels are re-bound.
        val plugins = PulsrEnginePlugins.obtain(flutterEngine, applicationContext)
        plugins.tagEditor.attachActivity(this)
        bindActivityChannels(flutterEngine)
    }

    private fun bindActivityChannels(flutterEngine: FlutterEngine) {
        synchronized(activeActivityByEngine) {
            activeActivityByEngine[flutterEngine] = this
        }
        if (activityChannelsBound && boundFlutterEngine === flutterEngine) return
        boundFlutterEngine = flutterEngine
        activityChannelsBound = true

        val fileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPENER_CHANNEL)
        fileOpenerChannel = fileChannel
        fileChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAudioUri" -> {
                    val uri = synchronized(pendingAudioUris) {
                        pendingAudioUris.removeFirstOrNull()
                    }
                    result.success(uri)
                }
                "getInitialAudioUris" -> {
                    val uris = synchronized(pendingAudioUris) {
                        val copy = pendingAudioUris.toList()
                        pendingAudioUris.clear()
                        copy
                    }
                    result.success(uris)
                }
                else -> result.notImplemented()
            }
        }

        // Assistant suggestion cache (P1-9): Dart pushes the suggestion rows,
        // the exported SearchSuggestionsProvider serves them to system search.
        // The provider is read-only and holds no paths or credentials.
        val assistantChan = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ASSISTANT_CHANNEL
        )
        assistantChannel = assistantChan
        assistantChan.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart handshake: the intent service now owns the channel.
                // Flush search intents received before the handler existed.
                "assistantReady" -> {
                    assistantReady = true
                    flushPendingAssistantExtras(assistantChan)
                    result.success(true)
                }
                "updateSuggestions" -> {
                    val rows = (call.arguments as? List<*>)?.mapNotNull { raw ->
                        val map = raw as? Map<*, *> ?: return@mapNotNull null
                        mapOf(
                            "title" to (map["title"] as? String).orEmpty(),
                            "subtitle" to (map["subtitle"] as? String).orEmpty(),
                            "query" to (map["query"] as? String).orEmpty()
                        )
                    }.orEmpty()
                    try {
                        SearchSuggestionsProvider.pushSuggestions(this, rows)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Failed to cache search suggestions: ${e.message}")
                        result.error("SUGGESTIONS_FAILED", e.message, null)
                    }
                }
                "clear" -> {
                    try {
                        SearchSuggestionsProvider.clearSuggestions(this)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Failed to clear search suggestions: ${e.message}")
                        result.error("SUGGESTIONS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Probe the Dart handler: it may already be installed (audio_service
        // keeps the engine alive while the Activity is recreated), in which
        // case pending search intents can be flushed without waiting for a new
        // handshake.
        assistantChan.invokeMethod("isReady", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                assistantReady = true
                flushPendingAssistantExtras(assistantChan)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
            override fun notImplemented() = Unit
        })

        val lyricsChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LYRICS_CHANNEL)
        lyricsChannel = lyricsChan
        lyricsChan.setMethodCallHandler { call, result ->
            if (call.method == "getEmbeddedLyrics") {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "File path is null", null)
                    return@setMethodCallHandler
                }
                lyricsExecutor.execute {
                    var lyrics: String? = null
                    var tempFile: File? = null
                    val isContentUri = filePath.startsWith("content:")
                    try {
                        fun readFrom(file: File): String? {
                            var found: String? = null
                            // 1) jaudiotagger – LYRICS key (widely supported)
                            try {
                                val audioFile = AudioFileIO.read(file)
                                found = audioFile.tag?.getFirst(FieldKey.LYRICS)
                                // 1b) FLAC/OGG store lyrics in Vorbis comments, but
                                // most taggers write UNSYNCEDLYRICS / SYNCEDLYRICS,
                                // which jaudiotagger 3.x has no FieldKey mapping for
                                // (only "LYRICS" is mapped). Probe those keys by raw
                                // name on the Vorbis-backed tags or they are missed.
                                // SYNCED is preferred over UNSYNCED when both exist
                                // (reader ids are uppercased on read, so these exact
                                // names match any letter case the tagger used).
                                if (found.isNullOrBlank()) {
                                    val vorbisTag: AbstractTag? = when (val tag = audioFile.tag) {
                                        is FlacTag -> tag.vorbisCommentTag
                                        is VorbisCommentTag -> tag
                                        is AbstractTag -> tag
                                        else -> null
                                    }
                                    if (vorbisTag != null) {
                                        for (key in listOf(
                                            "SYNCEDLYRICS",
                                            "UNSYNCEDLYRICS",
                                            "SYNCED LYRICS",
                                            "UNSYNCED LYRICS"
                                        )) {
                                            val v = vorbisTag.getFirst(key)
                                            if (!v.isNullOrBlank()) {
                                                found = v
                                                break
                                            }
                                        }
                                    }
                                }
                            } catch (_: Exception) {}
                            // 2) MediaMetadataRetriever fallback – some OEMs write lyrics that jaudiotagger misses
                            if (found.isNullOrBlank()) {
                                var retriever: MediaMetadataRetriever? = null
                                try {
                                    retriever = MediaMetadataRetriever()
                                    if (isContentUri) {
                                        retriever.setDataSource(applicationContext, Uri.parse(filePath))
                                    } else {
                                        retriever.setDataSource(file.absolutePath)
                                    }
                                    // No dedicated lyrics key in MediaMetadataRetriever, but try writer/lyricist
                                    val fallbackKeys = listOf(
                                        MediaMetadataRetriever.METADATA_KEY_WRITER,
                                        MediaMetadataRetriever.METADATA_KEY_AUTHOR
                                    )
                                    for (k in fallbackKeys) {
                                        val v = retriever.extractMetadata(k)
                                        if (!v.isNullOrBlank() && v.contains("\n")) {
                                            found = v; break
                                        }
                                    }
                                } catch (_: Exception) {} finally {
                                    try { retriever?.release() } catch (_: Exception) {}
                                }
                            }
                            return found
                        }

                        if (isContentUri) {
                            val uri = Uri.parse(filePath)
                            val cap = 16L * 1024 * 1024
                            // Lyrics tags live in the header or at the tail;
                            // 16 MB is enough for almost every file. Only fall
                            // back to a full copy when parsing the head failed.
                            tempFile = AudioTempFiles.copyToTempFile(
                                applicationContext,
                                uri,
                                "lyrics_",
                                cap,
                                throwOnOverflow = false,
                            )
                            val truncated = tempFile.length() >= cap
                            lyrics = readFrom(tempFile)
                            if (lyrics.isNullOrBlank() && truncated) {
                                runCatching { tempFile.delete() }
                                val fallbackCap = 32L * 1024 * 1024
                                val fullTemp = AudioTempFiles.copyToTempFile(
                                    applicationContext,
                                    uri,
                                    "lyrics_full_",
                                    maxBytes = fallbackCap,
                                    throwOnOverflow = false,
                                )
                                tempFile = fullTemp
                                if (fullTemp.length() >= fallbackCap) {
                                    Log.w(
                                        "MainActivity",
                                        "Skipping embedded lyrics fallback for oversized content URI (>= 32 MB)",
                                    )
                                    lyrics = null
                                } else {
                                    lyrics = readFrom(fullTemp)
                                }
                            }
                        } else {
                            val file = File(filePath)
                            if (file.exists() && file.canRead()) {
                                lyrics = readFrom(file)
                            } else {
                                val uri = if (filePath.startsWith("file://")) Uri.parse(filePath) else Uri.fromFile(file)
                                val resolvedUri = resolveFileUriToContentUri(uri) ?: uri
                                runCatching {
                                    val fallbackTemp = AudioTempFiles.copyToTempFile(
                                        applicationContext,
                                        resolvedUri,
                                        "lyrics_fallback_",
                                        16L * 1024 * 1024,
                                        throwOnOverflow = false,
                                    )
                                    tempFile = fallbackTemp
                                    lyrics = readFrom(fallbackTemp)
                                }
                            }
                        }
                        runOnUiThread { runCatching { result.success(lyrics) } }
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Embedded lyrics extraction failed for $filePath: ${e.message}")
                        runOnUiThread { runCatching { result.success(null) } }
                    } finally {
                        tempFile?.let { runCatching { it.delete() } }
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        // Pulsr Pure runtime guarantee: report whether the merged manifest
        // actually carries the INTERNET permission, so the Dart layer can
        // detect a bad manifest merge that would silently add network access.
        val purityChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/purity")
        purityChannel = purityChan
        purityChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasInternetPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        checkSelfPermission(android.Manifest.permission.INTERNET) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    } else {
                        packageManager.checkPermission(
                            android.Manifest.permission.INTERNET,
                            packageName) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    }
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        }

        val batteryChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/battery_optimization")
        batteryChannel = batteryChan
        batteryChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(isIgnoring)
                    } else {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("BATTERY_OPT_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }
                "openOemBatterySettings" -> {
                    val opened = tryOpenOemBatterySettings()
                    result.success(opened)
                }
                "getBatteryLevel" -> {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
                    val level = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
                    result.success(level)
                }
                "getTotalRamBytes" -> {
                    val actManager = getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                    val memInfo = android.app.ActivityManager.MemoryInfo()
                    actManager?.getMemoryInfo(memInfo)
                    result.success(memInfo.totalMem)
                }
                else -> result.notImplemented()
            }
        }

        // Playback-state hook for the Quick Settings tile. Dart calls
        // setPlaying whenever the audio handler's playing state changes.
        val tileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/playback_tile")
        playbackTileChannel = tileChannel
        tileChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPlaying" -> {
                    PlaybackTileState.setPlaying(
                        applicationContext,
                        call.argument<Boolean>("playing") ?: false
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/updater")
        updaterChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    // The Play Store (prod) flavor ships without
                    // REQUEST_INSTALL_PACKAGES; self-update is dev/ytm only.
                    if (BuildConfig.FLAVOR == "prod") {
                        result.error("UNSUPPORTED", "In-app APK install is not available in this build", null)
                        return@setMethodCallHandler
                    }
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARG", "File path cannot be null", null)
                        return@setMethodCallHandler
                    }
                    val file = File(filePath)
                    val allowedRoots = listOfNotNull(cacheDir, filesDir, getExternalFilesDir(null))
                    val canonical = try {
                        file.canonicalFile
                    } catch (e: Exception) {
                        result.error("INVALID_PATH", "Cannot resolve APK path: ${e.message}", null)
                        return@setMethodCallHandler
                    }
                    val insideAllowedRoot = allowedRoots.any { root ->
                        val rootPath = try { root.canonicalPath } catch (_: Exception) { root.path }
                        canonical.path.startsWith(rootPath + File.separator)
                    }
                    if (!insideAllowedRoot) {
                        result.error("INVALID_PATH", "APK path must be inside app storage", null)
                        return@setMethodCallHandler
                    }
                    if (!canonical.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(settingsIntent)
                            result.success("REQUESTED_PERMISSION")
                            return@setMethodCallHandler
                        }
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this@MainActivity,
                            "$packageName.fileprovider",
                            canonical
                        )
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                            putExtra(Intent.EXTRA_RETURN_RESULT, true)
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        }
                        startActivity(installIntent)
                        result.success("INSTALLING")
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Failed to install APK: ${e.message}", e)
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "canRequestPackageInstalls" -> {
                    val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(canInstall)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Only Activity-scoped references may be dropped here. The cached
        // FlutterEngine (and playback) outlives this Activity; engine-scoped
        // plugins are torn down by PulsrEnginePlugins when the engine itself is
        // destroyed, never while the service is still playing.
        val stillOwner = synchronized(activeActivityByEngine) {
            if (activeActivityByEngine[flutterEngine] === this) {
                activeActivityByEngine.remove(flutterEngine)
                true
            } else {
                false
            }
        }
        PulsrEnginePlugins.find(flutterEngine)?.tagEditor?.detachActivity(this)
        if (boundFlutterEngine === flutterEngine) {
            boundFlutterEngine = null
        }
        if (stillOwner) {
            updaterChannel?.setMethodCallHandler(null)
            playbackTileChannel?.setMethodCallHandler(null)
            purityChannel?.setMethodCallHandler(null)
            batteryChannel?.setMethodCallHandler(null)
            fileOpenerChannel?.setMethodCallHandler(null)
            assistantChannel?.setMethodCallHandler(null)
            lyricsChannel?.setMethodCallHandler(null)
        }
        updaterChannel = null
        playbackTileChannel = null
        purityChannel = null
        batteryChannel = null
        fileOpenerChannel = null
        assistantChannel = null
        lyricsChannel = null
        activityChannelsBound = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val handled = flutterEngine?.let { engine ->
            PulsrEnginePlugins.find(engine)?.tagEditor?.handleActivityResult(requestCode, resultCode, data)
        } == true
        if (handled) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun tryOpenOemBatterySettings(): Boolean {
        val oemIntents = listOf(
            // Xiaomi / POCO / Redmi (MIUI / HyperOS)
            Intent().setComponent(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"))
                .putExtra("package_name", packageName)
                .putExtra("package_label", applicationInfo.loadLabel(packageManager).toString()),
            Intent().setComponent(ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsContainerManagementActivity")),
            Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            // Samsung (One UI)
            Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")),
            Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")),
            Intent("com.samsung.android.lool.ACTION_BATTERY_OPTIMIZATION"),
            // Huawei / Honor
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")),
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")),
            // Oppo / Realme (ColorOS / RealmeUI)
            Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.oplus.battery", "com.oplus.battery.AppListActivity")),
            Intent().setComponent(ComponentName("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity")),
            // Vivo / iQOO
            Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")),
            Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.PurviewTabActivity")),
            // OnePlus (OxygenOS)
            Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")),
            // Standard App Details Settings (Works on all Android versions)
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        )

        for (intent in oemIntents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // Android 11+ hides un-queried OEM packages from resolveActivity(), so
                // attempt startActivity directly and fall through on missing/unexported
                // targets down to Settings.ACTION_APPLICATION_DETAILS_SETTINGS.
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            } catch (_: Exception) {
            }
        }
        return false
    }


    private fun registerStorageReceiver() {
        val filter = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_MEDIA_MOUNTED)
            addAction(Intent.ACTION_MEDIA_UNMOUNTED)
            addAction(Intent.ACTION_MEDIA_EJECT)
            addDataScheme("file")
        }
        mediaReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                runOnUiThread {
                    fileOpenerChannel?.invokeMethod("onMediaStoreChanged", null)
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(mediaReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(mediaReceiver, filter)
            }
        } catch (_: Exception) {}
    }


    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            synchronized(pendingAudioUris) {
                while (pendingAudioUris.size > 4) {
                    pendingAudioUris.removeFirstOrNull()
                }
            }
        }
    }

}
