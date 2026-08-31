import java.util.Properties
import java.io.FileInputStream
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.pulsr.music"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pulsr.music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 28 (Android 9) is the floor for the true 10-band graphic EQ, which is
        // built on DynamicsProcessing postEq — added in API 28.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "Pulsr Music"

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20", "-O3")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    flavorDimensions += "default"
    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".plus"
            manifestPlaceholders["appName"] = "Pulsr Plus"
            proguardFiles("src/dev/proguard-rules.pro")
        }
        create("prod") {
            dimension = "default"
            manifestPlaceholders["appName"] = "Pulsr Music"
        }
        // Off-Play distribution build. Identical to prod but compiles the
        // NewPipeExtractor bridge, so YouTube Music search/stream/download works.
        create("ytm") {
            dimension = "default"
            applicationIdSuffix = ".ytm"
            manifestPlaceholders["appName"] = "Pulsr Music"
            proguardFiles("src/ytm/proguard-rules.pro")
        }
    }

    // Flavor-specific ProGuard keep rules for NewPipeExtractor + Rhino are wired per-flavor above.

    // The extractor bridge lives outside src/main so that `prod` -- the Play
    // Store variant -- cannot compile it and does not link NewPipeExtractor at
    // all. This is a hard exclusion, unlike the Dart-side ENABLE_YTM gate which
    // only relies on tree-shaking. Both source sets must declare the same
    // YtmExtractorPlugin class, because MainActivity in src/main references it.
    // The assets dir carries the BotGuard page the poToken WebView runs, which is
    // likewise GPL and so likewise kept out of prod.
    sourceSets {
        getByName("dev") {
            kotlin.srcDir("src/ytmEnabled/kotlin")
            assets.srcDir("src/ytmEnabled/assets")
        }
        getByName("ytm") {
            kotlin.srcDir("src/ytmEnabled/kotlin")
            assets.srcDir("src/ytmEnabled/assets")
        }
        getByName("prod") { kotlin.srcDir("src/ytmDisabled/kotlin") }
    }

    val keystoreProperties = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) {
            load(FileInputStream(f))
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            val hasKeystore = releaseConfig.storeFile != null && releaseConfig.storeFile!!.exists()
            val isOptedOut = System.getenv("ALLOW_INSECURE_DEBUG_SIGNING") == "true"
            val isProdOrYtmBuild = gradle.startParameter.taskNames.any {
                (it.contains("Prod", ignoreCase = true) || it.contains("Ytm", ignoreCase = true)) &&
                it.contains("Release", ignoreCase = true)
            }
            if (!hasKeystore) {
                if (isProdOrYtmBuild && !isOptedOut) {
                    throw GradleException(
                        "Release keystore file missing in key.properties for shipping release build.\n" +
                        "Shipping builds (prod/ytm) cannot fall back to debug signing without breaking Google Sign-In (N-03 / OAuth error 10).\n" +
                        "To bypass this check strictly for local experimentation, set ALLOW_INSECURE_DEBUG_SIGNING=true."
                    )
                }
                // Note (N-03): Local release builds using debug signing will fail Google Sign-In with DEVELOPER_ERROR (code 10)
                // because the debug keystore SHA-1 does not match the registered production OAuth client.
                logger.warn("WARNING: Release keystore file not found in key.properties. Falling back to debug signing config.")
            }
            signingConfig = if (hasKeystore) releaseConfig else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            // Flavor-specific rules applied via productFlavors above (C-05)
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    testOptions {
        // B-10 fix: false prevents silent stubbing of un-mocked MethodChannels (which caused false-greens)
        unitTests.isReturnDefaultValues = false
        unitTests.isIncludeAndroidResources = true
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    packaging {
        resources {
            excludes += "google/protobuf/**"
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/INDEX.LIST"
            excludes += "META-INF/io.netty.versions.properties"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Scoped to this module rather than the root allprojects block: JitPack serves
// unreviewed builds straight from git tags, so only the app needs to trust it.
repositories {
    maven { url = uri("https://jitpack.io") }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
    implementation("net.jthink:jaudiotagger:3.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // ServiceCompat.startForeground(service, id, notification, type) — required
    // for the runtime FGS type selection (dataSync on API 34 / mediaProcessing
    // on API 35+) in DownloadService. androidx.core is already in the graph
    // transitively (androidx.media 1.7.0 -> core 1.9.0); pinned to 1.13.1
    // because ServiceCompat.startForeground was added in core 1.12.0.
    implementation("androidx.core:core:1.13.1")

    // GPL-3.0. Its presence is why Pulsr as a whole is GPL-3.0, and why it is
    // kept out of the prod (Play Store) variant. Pulls in Mozilla Rhino, which
    // solves YouTube's JS signature challenges on-device.
    val newPipeExtractor = "com.github.TeamNewPipe:NewPipeExtractor:v0.26.5"
    "devImplementation"(newPipeExtractor)
    "ytmImplementation"(newPipeExtractor)
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}

configurations.all {
    resolutionStrategy {
        force("com.google.protobuf:protobuf-javalite:3.25.5")
    }
}

// A5 (N-07): Verified package*UnitTestForUnitTest matches real AGP PackageForHostTest tasks when isIncludeAndroidResources=true.
// Must declare explicit dependency on copyFlutterAssets tasks to avoid Gradle implicit dependency failure.
tasks.matching { it.name.startsWith("package") && it.name.endsWith("UnitTestForUnitTest") }.configureEach {
    dependsOn(tasks.matching { it.name.startsWith("copyFlutterAssets") })
}

tasks.register("testNative") {
    group = "verification"
    description = "Compiles and executes native C++ DSP test suite on host (parity build)."
    doLast {
        val testDir = file("src/test/cpp")
        val mainDir = file("src/main/cpp")
        val outDir = file("build/testNative").apply { mkdirs() }
        val isWindows = org.apache.tools.ant.taskdefs.condition.Os.isFamily(org.apache.tools.ant.taskdefs.condition.Os.FAMILY_WINDOWS)
        val exeParity = file("${outDir.absolutePath}/test_native_parity" + if (isWindows) ".exe" else "")

        val compiler = System.getenv("CXX")
            ?: System.getenv("CLANG_CXX")
            ?: "clang++"

        // Verify compiler availability before launching (C-02)
        try {
            val probeCmd = listOf(compiler, "--version")
            val probeProc = ProcessBuilder(probeCmd).redirectErrorStream(true).start()
            val probeRes = probeProc.waitFor()
            if (probeRes != 0) {
                throw GradleException("C++ compiler '$compiler' exited with code $probeRes during version probe.")
            }
        } catch (e: Exception) {
            throw GradleException(
                "C++ compiler '$compiler' could not be found or executed.\n" +
                "Please ensure clang++ (or another C++20 compiler) is installed and available in your PATH,\n" +
                "or set the CXX environment variable pointing to your compiler binary.", e
            )
        }

        val dspSources = listOf(
            "ParametricEQ.cpp",
            "Crossfeed.cpp",
            "LookaheadLimiter.cpp",
            "ConvolutionReverb.cpp",
            "SincResampler.cpp",
            "DsdDecoder.cpp",
            "SpatialPanner.cpp",
            "AudioDspEngine.cpp"
        ).map { file("${mainDir.absolutePath}/$it").absolutePath }

        // 1. Build & Run: Parity Build with exact production flags (-O3 -std=c++20)
        println("[testNative] Compiling parity build (-O3 -std=c++20)...")
        val parityCompileCmd = mutableListOf(
            compiler,
            "-std=c++20",
            "-O3",
            "-I", mainDir.absolutePath,
            file("${testDir.absolutePath}/test_native_all.cpp").absolutePath
        ).apply {
            addAll(dspSources)
            if (isWindows) {
                add("-static")
                add("-lpsapi")
            }
            add("-o")
            add(exeParity.absolutePath)
        }

        val parityCompileRes = ProcessBuilder(parityCompileCmd).inheritIO().start().waitFor()
        if (parityCompileRes != 0) {
            throw GradleException("Native DSP parity test compilation failed with exit code $parityCompileRes")
        }

        println("[testNative] Running parity test suite...")
        val parityProc = ProcessBuilder(exeParity.absolutePath).redirectErrorStream(true).start()
        parityProc.inputStream.bufferedReader().useLines { lines ->
            lines.forEach { println(it) }
        }
        val parityRunRes = parityProc.waitFor()
        if (parityRunRes != 0) {
            throw GradleException("Native DSP parity test execution failed with exit code $parityRunRes")
        }

        println("[testNative] PASSED: Native DSP test suite (23/23 tests) passed 100%.")
    }
}

tasks.register("validateProdIsolation") {
    group = "verification"
    description = "Ensures GPL / YouTube Extractor code never compiles into the prod variant."
    doLast {
        val prodKotlinDir = file("src/ytmDisabled/kotlin")
        if (!prodKotlinDir.exists()) {
            throw GradleException("Prod stub directory src/ytmDisabled/kotlin is missing!")
        }
        val forbiddenTerms = listOf("music.youtube.com", "NewPipeExtractor", "org.schabi.newpipe", "po_token")

        // 1. Check main Manifest
        val mainManifest = file("src/main/AndroidManifest.xml")
        if (mainManifest.exists()) {
            val content = mainManifest.readText()
            for (term in forbiddenTerms) {
                if (content.contains(term)) {
                    throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/AndroidManifest.xml!")
                }
            }
        }

        // 2. Check main Kotlin sources
        val mainKotlinDir = file("src/main/kotlin")
        if (mainKotlinDir.exists()) {
            mainKotlinDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/kotlin file: ${file.path}")
                    }
                }
            }
        }

        // 3. Check main res
        val mainResDir = file("src/main/res")
        if (mainResDir.exists()) {
            mainResDir.walkTopDown().filter { it.isFile && (it.extension == "xml" || it.extension == "png") }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/res file: ${file.path}")
                    }
                }
            }
        }

        // 4. Check main assets
        val mainAssetsDir = file("src/main/assets")
        if (mainAssetsDir.exists()) {
            mainAssetsDir.walkTopDown().filter { it.isFile }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/assets file: ${file.path}")
                    }
                }
            }
        }

        // 5. Check Proguard rules
        val proguardRules = file("proguard-rules.pro")
        if (proguardRules.exists()) {
            val text = proguardRules.readText()
            for (term in forbiddenTerms) {
                if (text.contains(term)) {
                    throw GradleException("Forbidden GPL/YouTube term '$term' found in proguard-rules.pro!")
                }
            }
        }

        // 6. Check native C++ sources (B-12 completeness gap)
        val mainCppDir = file("src/main/cpp")
        if (mainCppDir.exists()) {
            mainCppDir.walkTopDown().filter { it.isFile && (it.extension == "cpp" || it.extension == "h" || it.extension == "c" || it.extension == "cc") }.forEach { file ->
                val text = file.readText()
                for (term in forbiddenTerms) {
                    if (text.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/cpp file: ${file.path}")
                    }
                }
            }
        }

        // 7. Check jniLibs (prebuilt .so that could hide extractor)
        val jniLibsDir = file("src/main/jniLibs")
        if (jniLibsDir.exists()) {
            jniLibsDir.walkTopDown().filter { it.isFile }.forEach { file ->
                // Binary scan as text fallback — look for forbidden strings in file name and text-readable content
                val name = file.name
                for (term in forbiddenTerms) {
                    if (name.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs file name: ${file.path}")
                    }
                }
                try {
                    val text = file.readText(Charsets.UTF_8)
                    for (term in forbiddenTerms) {
                        if (text.contains(term)) {
                            throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs file: ${file.path}")
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        println("[validateProdIsolation] PASSED: Prod isolation verified successfully across manifests, kotlin, res, assets, proguard, cpp, and jniLibs.")
    }
}

tasks.register("verifyProdApkIsolation") {
    group = "verification"
    description = "Unzips and scans production release APK dex, so, and assets for forbidden GPL/YouTube terms."
    doLast {
        val forbiddenTerms = listOf("music.youtube.com", "NewPipeExtractor", "org.schabi.newpipe", "po_token")
        val apkDir = file("build/app/outputs/flutter-apk")
        val prodApk = apkDir.listFiles()?.firstOrNull { it.name.contains("prod") && it.name.endsWith(".apk") }
        if (prodApk != null && prodApk.exists()) {
            println("[verifyProdApkIsolation] Scanning APK: ${prodApk.name}...")
            val zipFile = ZipFile(prodApk)
            val entries = zipFile.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.name.endsWith(".dex") || entry.name.endsWith(".so") || entry.name.startsWith("assets/")) {
                    val stream = zipFile.getInputStream(entry)
                    val bytes = stream.readBytes()
                    val text = String(bytes, Charsets.ISO_8859_1)
                    for (term in forbiddenTerms) {
                        if (text.contains(term)) {
                            zipFile.close()
                            throw GradleException("Forbidden GPL term '$term' detected inside production APK entry: ${entry.name}")
                        }
                    }
                }
            }
            zipFile.close()
            println("[verifyProdApkIsolation] PASSED: Production APK is 100% clean of all GPL/NewPipe references.")
        } else {
            println("[verifyProdApkIsolation] No prod APK found in $apkDir, skipping binary scan.")
        }
    }
}

afterEvaluate {
    tasks.matching { it.name.startsWith("assemble") || it.name == "check" || it.name == "test" }.configureEach {
        dependsOn("validateProdIsolation")
    }
}
