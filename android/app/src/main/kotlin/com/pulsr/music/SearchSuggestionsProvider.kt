package com.pulsr.music

import android.app.SearchManager
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Suggestion source for the system search surface used by the assistant.
 *
 * The Flutter layer owns the library, so it pushes the rows it wants offered
 * over the `com.pulsr.music/assistant` channel; this provider only stores them
 * (SharedPreferences, small cap) and answers suggestion queries with
 * `SearchManager.SUGGEST_COLUMN_*` columns. Queries run on a binder thread and
 * never touch the music database.
 *
 * Wiring: declare the provider with `${applicationId}.suggestions` in
 * AndroidManifest and point `res/xml/searchable.xml` at the same authority for
 * each flavor. [authority] derives the runtime value from the installed
 * package, so a flavor with an `applicationIdSuffix` never looks at another
 * flavor's cache.
 */
class SearchSuggestionsProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val providerContext = context
        if (providerContext == null) {
            Log.w(TAG, "Suggestion query without a provider context")
            return emptyCursor(projection)
        }
        return try {
            buildCursor(providerContext, uri, projection, selection, selectionArgs)
        } catch (e: Exception) {
            Log.w(TAG, "Suggestion query failed: ${e.message}")
            emptyCursor(projection)
        }
    }

    override fun getType(uri: Uri): String? = CONTENT_TYPE

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    /** Builds the suggestion cursor for one `search_suggest_query` request. */
    private fun buildCursor(
        context: Context,
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Cursor {
        val columns = columnsFor(projection)
        val cursor = MatrixCursor(columns)
        val rows = readRows(context)
        if (rows.isEmpty()) return cursor
        val term = queryTerm(uri, selection, selectionArgs)
        val limit = limitOf(uri)
        var accepted = 0
        for (row in rows) {
            if (accepted >= limit) break
            if (!row.matches(term)) continue
            cursor.addRow(
                columns.map { column -> valueFor(column, row, accepted) }.toTypedArray()
            )
            accepted++
        }
        return cursor
    }

    /** Empty cursor with the same shape as a filled one. */
    private fun emptyCursor(projection: Array<out String>?): MatrixCursor =
        MatrixCursor(columnsFor(projection))

    /**
     * Resolves the search term.
     *
     * The search framework passes `selection = " ?"` plus the typed text in
     * `selectionArgs`; launchers sometimes append the term to the URI instead.
     * Honour the args first, then the path/query forms.
     */
    private fun queryTerm(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?
    ): String {
        val fromArgs = selectionArgs
            ?.asSequence()
            ?.firstOrNull { it.isNotBlank() }
        if (fromArgs != null) return normalizeTerm(fromArgs)
        val last = uri.lastPathSegment
        val raw = when {
            last == null || last == PATH_QUERY || last == PATH_SHORTCUT ->
                uri.getQueryParameter(SearchManager.QUERY)
                    .orEmpty()
            else -> last
        }
        if (raw.isBlank() && !selection.isNullOrBlank() && selection != SELECTION_PLACEHOLDER) {
            // A few hosts put the term in selection without args; it is data,
            // never executed as SQL.
            return normalizeTerm(selection)
        }
        return normalizeTerm(raw)
    }

    private fun normalizeTerm(raw: String): String =
        raw.trim().lowercase().removePrefix("play ").trim()

    /** Honours the `limit` parameter the search framework appends. */
    private fun limitOf(uri: Uri): Int {
        val raw = uri.getQueryParameter(SearchManager.SUGGEST_PARAMETER_LIMIT) ?: return DEFAULT_LIMIT
        return raw.toIntOrNull()?.coerceIn(1, MAX_SUGGESTIONS) ?: DEFAULT_LIMIT
    }

    /** Uses the caller's projection when it supplies one, else our defaults. */
    private fun columnsFor(projection: Array<out String>?): Array<String> =
        if (projection.isNullOrEmpty()) DEFAULT_COLUMNS else projection.toList().toTypedArray()

    /** Maps one [SuggestionRow] onto a `SearchManager.SUGGEST_COLUMN_*` column. */
    private fun valueFor(column: String, row: SuggestionRow, index: Int): Any? = when (column) {
        "_id" -> index.toLong()
        SearchManager.SUGGEST_COLUMN_TEXT_1 -> row.title
        SearchManager.SUGGEST_COLUMN_TEXT_2 -> row.subtitle
        SearchManager.SUGGEST_COLUMN_QUERY -> row.query
        SearchManager.SUGGEST_COLUMN_INTENT_ACTION -> ACTION_PLAY_FROM_SEARCH
        else -> null
    }

    /** One cached suggestion row plus its matching rule. */
    private data class SuggestionRow(
        val title: String,
        val subtitle: String,
        val query: String
    ) {
        /** True when [term] appears in the title or the submitted query. */
        fun matches(term: String): Boolean {
            if (term.isEmpty()) return true
            val title = title.lowercase()
            val query = query.lowercase()
            return title.contains(term) ||
                query.contains(term) ||
                title.removePrefix("the ").contains(term)
        }
    }

    companion object {
        /**
         * Provider authority suffix.
         *
         * The manifest declares `${applicationId}.suggestions`; resolving it
         * from [Context.getPackageName] at runtime keeps dev/ytm flavors (which
         * add an `applicationIdSuffix`) on their own cache.
         */
        const val AUTHORITY_SUFFIX = ".suggestions"

        /**
         * Production authority, retained for documentation and older callers.
         * Never use it to build a Uri at runtime; use [authority] instead.
         */
        @Deprecated("Use authority(context) so flavors keep separate caches")
        const val AUTHORITY = "com.pulsr.music.suggestions"

        /** Runtime authority for the installed flavor. */
        fun authority(context: Context): String =
            "${context.packageName}$AUTHORITY_SUFFIX"

        /** `SearchRecentSuggestions.SUGGEST_URI_PATH_QUERY`. */
        const val PATH_QUERY = "search_suggest_query"

        /** `SearchRecentSuggestions.SUGGEST_URI_PATH_SHORTCUT`. */
        const val PATH_SHORTCUT = "search_suggest_shortcut"

        /** `android:searchSuggestSelection` value used by the search UI. */
        private const val SELECTION_PLACEHOLDER = " ?"

        private const val CONTENT_TYPE = "vnd.android.cursor.dir/vnd.android.search_suggestions"
        private const val TAG = "SearchSuggestions"
        private const val ACTION_PLAY_FROM_SEARCH = "android.media.action.MEDIA_PLAY_FROM_SEARCH"
        private const val PREFS_NAME = "pulsr_search_suggestions"
        private const val KEY_ROWS = "rows"
        private const val KEY_TITLE = "title"
        private const val KEY_SUBTITLE = "subtitle"
        private const val KEY_QUERY = "query"
        private const val MAX_STORED_ROWS = 40
        private const val MAX_SUGGESTIONS = 12
        private const val DEFAULT_LIMIT = 8

        private val DEFAULT_COLUMNS = arrayOf(
            "_id",
            SearchManager.SUGGEST_COLUMN_TEXT_1,
            SearchManager.SUGGEST_COLUMN_TEXT_2,
            SearchManager.SUGGEST_COLUMN_QUERY,
            SearchManager.SUGGEST_COLUMN_INTENT_ACTION
        )

        /**
         * Replaces the cached rows with [rows].
         *
         * Rows without a title or a query are dropped, and the list is capped
         * at [MAX_STORED_ROWS] so the prefs entry stays small. Storage errors
         * are logged, never thrown, because this runs inside a channel handler.
         */
        fun pushSuggestions(context: Context, rows: List<Map<String, String>>) {
            val payload = JSONArray()
            rows.asSequence()
                .filter { !it[KEY_QUERY].isNullOrBlank() }
                .take(MAX_STORED_ROWS)
                .forEach { row ->
                    val title = row[KEY_TITLE].orEmpty().trim()
                    if (title.isEmpty()) return@forEach
                    payload.put(
                        JSONObject()
                            .put(KEY_TITLE, title)
                            .put(KEY_SUBTITLE, row[KEY_SUBTITLE].orEmpty().trim())
                            .put(KEY_QUERY, row[KEY_QUERY].orEmpty().trim())
                    )
                }
            try {
                prefs(context).edit().putString(KEY_ROWS, payload.toString()).apply()
            } catch (e: Exception) {
                Log.w(TAG, "Saving suggestions failed: ${e.message}")
            }
        }

        /** Drops every cached row. */
        fun clearSuggestions(context: Context) {
            try {
                prefs(context).edit().remove(KEY_ROWS).apply()
            } catch (e: Exception) {
                Log.w(TAG, "Clearing suggestions failed: ${e.message}")
            }
        }

        private fun prefs(context: Context): SharedPreferences =
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /** Reads the cached rows, returning an empty list on corrupt storage. */
        private fun readRows(context: Context): List<SuggestionRow> {
            val raw = try {
                prefs(context).getString(KEY_ROWS, null)
            } catch (e: Exception) {
                Log.w(TAG, "Reading suggestions failed: ${e.message}")
                null
            } ?: return emptyList()
            return try {
                val array = JSONArray(raw)
                (0 until array.length()).mapNotNull { index ->
                    val entry = array.optJSONObject(index) ?: return@mapNotNull null
                    val title = entry.optString(KEY_TITLE).trim()
                    val query = entry.optString(KEY_QUERY).trim()
                    if (title.isEmpty() || query.isEmpty()) return@mapNotNull null
                    SuggestionRow(title, entry.optString(KEY_SUBTITLE).trim(), query)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Parsing suggestions failed: ${e.message}")
                emptyList()
            }
        }
    }
}
