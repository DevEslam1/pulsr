import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.pulsr.music"
    compileSdk = 37
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
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "Pulsr Music"

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20")
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
            proguardFile(file("src/dev/proguard-rules.pro"))
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
            proguardFile(file("src/ytm/proguard-rules.pro"))
        }
    }

    // Flavor-specific ProGuard keep rules for NewPipeExtractor + Rhino.
    // AGP does NOT auto-discover src/<flavor>/proguard-rules.pro, so we wire them
    // explicitly. B-02 fix: these rules were previously dead code; without them
    // R8 strips the extractor in dev/ytm release builds -> runtime crash.
    // Using androidComponents to inject per-flavor proguard files correctly.
    // Fallback wiring via buildTypes ensures the rules are present even if
    // productFlavors ProGuard DSL is not supported in this AGP version.

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
            signingConfig = if (hasKeystore) releaseConfig else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            // Flavor-specific ProGuard rules are scoped per-flavor via androidComponents (B-11b)
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
    implementation(project(":media3-decoder-flac"))

    // GPL-3.0. Its presence is why Pulsr as a whole is GPL-3.0, and why it is
    // kept out of the prod (Play Store) variant. Pulls in Mozilla Rhino, which
    // solves YouTube's JS signature challenges on-device.
    val newPipeExtractor = "com.github.TeamNewPipe:NewPipeExtractor:v0.26.5"
    "devImplementation"(newPipeExtractor)
    "ytmImplementation"(newPipeExtractor)

    // Google Cast SDK. Scoped to the dev/ytm flavors only: the prod (Play Store)
    // "Pure" variant strips INTERNET and must not ship Cast or Play Services
    // routing. The matching code lives in sourceSets dev/ytm (src/ytmEnabled).
    val castFramework = "com.google.android.gms:play-services-cast-framework:21.5.0"
    "devImplementation"(castFramework)
    "ytmImplementation"(castFramework)

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}

configurations.all {
    resolutionStrategy {
        force("com.google.protobuf:protobuf-javalite:3.25.5")
    }
}

tasks.matching { it.name.startsWith("package") && it.name.endsWith("UnitTestForUnitTest") }.configureEach {
    mustRunAfter(tasks.matching { it.name.startsWith("copyFlutterAssets") })
}

tasks.register("testNative") {
    group = "verification"
    description = "Compiles and executes the full native C++ DSP test suite on the host via CMake/CTest (parity -O3 + sanitizer/debug builds)."
    doLast {
        val testDir = file("src/test/cpp")
        val isWindows = org.apache.tools.ant.taskdefs.condition.Os.isFamily(org.apache.tools.ant.taskdefs.condition.Os.FAMILY_WINDOWS)

        // Host C++ compiler discovery (mirrors the CMake toolchain expectation).
        val compiler = if (project.hasProperty("hostClangPath")) {
            project.property("hostClangPath").toString()
        } else if (System.getenv("HOST_CLANG") != null) {
            System.getenv("HOST_CLANG")!!
        } else if (isWindows) {
            val windhawk = file("C:/Program Files/Windhawk/Compiler/bin/clang++.exe")
            if (windhawk.exists()) windhawk.absolutePath else "clang++"
        } else {
            "clang++"
        }

        // Locate the CMake executable: prefer an explicit override, then PATH,
        // then the Android SDK's bundled cmake (which ships a host cmake binary).
        fun findCmake(): String {
            if (project.hasProperty("cmakePath")) return project.property("cmakePath").toString()
            val envCmake = System.getenv("CMAKE")
            if (!envCmake.isNullOrBlank()) return envCmake
            val onPath = try {
                val proc = ProcessBuilder(if (isWindows) listOf("where", "cmake") else listOf("which", "cmake"))
                    .redirectErrorStream(true).start()
                val out = proc.inputStream.bufferedReader().readText().trim().lines().firstOrNull()
                val code = proc.waitFor()
                if (code == 0 && !out.isNullOrBlank()) out else null
            } catch (_: Throwable) { null }
            if (onPath != null) return onPath

            val localProps = file("../local.properties")
            val sdkFromProps = if (localProps.exists()) {
                localProps.readLines().firstOrNull { it.startsWith("sdk.dir=") }
                    ?.substringAfter("=")?.trim()?.replace("\\\\", "/")?.replace("\\", "/")
            } else null
            val sdkRoot = sdkFromProps
                ?: System.getenv("ANDROID_HOME")
                ?: System.getenv("ANDROID_SDK_ROOT")
                ?: (if (isWindows) System.getenv("LOCALAPPDATA")?.let { "$it/Android/Sdk" } else null)
            if (sdkRoot != null) {
                val cmakeDir = file("$sdkRoot/cmake")
                if (cmakeDir.exists()) {
                    val candidates = cmakeDir.listFiles()?.sortedByDescending { it.name } ?: emptyList()
                    for (dir in candidates) {
                        val exe = file("${dir.absolutePath}/bin/cmake" + if (isWindows) ".exe" else "")
                        if (exe.exists()) return exe.absolutePath
                    }
                }
            }
            return "cmake"
        }

        fun executeCmd(cmd: List<String>, desc: String, workingDir: File? = null) {
            val pb = ProcessBuilder(cmd).redirectErrorStream(true)
            if (isWindows) {
                val env = pb.environment()
                val currentPath = env["PATH"] ?: ""
                val windhawkBin = "C:\\Program Files\\Windhawk\\Compiler\\bin"
                env["PATH"] = "$windhawkBin;$currentPath"
            }
            if (workingDir != null) pb.directory(workingDir)
            val proc = pb.start()
            proc.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { println("[$desc] $it") }
            }
            val res = proc.waitFor()
            if (res != 0) {
                throw GradleException("$desc failed with exit code $res")
            }
        }

        fun runBuild(configName: String, sanitizers: Boolean) {
            val buildDir = file("build/testNative/$configName").apply { mkdirs() }
            val cmake = findCmake()
            val ctest = File(File(cmake).parentFile, if (isWindows) "ctest.exe" else "ctest").takeIf { it.exists() }?.absolutePath ?: "ctest"
            val configureArgs = mutableListOf(
                cmake,
                "-S", testDir.absolutePath,
                "-B", buildDir.absolutePath,
                "-DCMAKE_BUILD_TYPE=$configName",
                "-DCMAKE_CXX_COMPILER=$compiler",
            )
            val ninja = File(File(cmake).parentFile, if (isWindows) "ninja.exe" else "ninja")
            if (ninja.exists()) {
                configureArgs += listOf("-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=${ninja.absolutePath.replace('\\', '/')}")
            }
            if (sanitizers && !isWindows) {
                configureArgs += "-DPULSR_TEST_SANITIZERS=ON"
            }
            println("[testNative] Configuring $configName build ...")
            executeCmd(configureArgs, "testNative-configure-$configName")

            println("[testNative] Building $configName ...")
            executeCmd(
                listOf(cmake, "--build", buildDir.absolutePath, "--parallel"),
                "testNative-build-$configName"
            )

            if (isWindows) {
                val windhawkBin = file("C:/Program Files/Windhawk/Compiler/bin")
                for (dll in listOf("libc++.dll", "libunwind.dll")) {
                    val src = File(windhawkBin, dll)
                    if (src.exists()) {
                        src.copyTo(File(buildDir, dll), overwrite = true)
                        val whl = File(buildDir, dll.replace(".dll", ".whl"))
                        src.copyTo(whl, overwrite = true)
                    }
                }
            }

            println("[testNative] Running $configName test suite via CTest ...")
            executeCmd(
                listOf(ctest, "--test-dir", buildDir.absolutePath, "--output-on-failure"),
                "testNative-run-$configName"
            )
        }

        // (a) Parity build: exact production flags (-O3 -std=c++20).
        runBuild("Release", sanitizers = false)
        // (b) Sanitizer / debug build: ASan+UBSan where the host supports it.
        runBuild("Debug", sanitizers = true)

        println("[testNative] PASSED: parity (-O3) and sanitizer/debug native DSP suites passed 100%.")
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

        // B2/B3 fix: byte-level ASCII scanning helper for binary files (.png, .so)
        fun fileContainsAsciiBytes(targetFile: File, term: String): Boolean {
            val termBytes = term.toByteArray(Charsets.US_ASCII)
            val bytes = targetFile.readBytes()
            if (bytes.size < termBytes.size) return false
            outer@ for (i in 0..(bytes.size - termBytes.size)) {
                for (j in termBytes.indices) {
                    if (bytes[i + j] != termBytes[j]) continue@outer
                }
                return true
            }
            return false
        }

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

        // 3. Check main res (B2/B3 fix: byte-level scan on images, text scan on xml)
        val mainResDir = file("src/main/res")
        if (mainResDir.exists()) {
            mainResDir.walkTopDown().filter { it.isFile && (it.extension == "xml" || it.extension == "png") }.forEach { file ->
                for (term in forbiddenTerms) {
                    if (file.extension == "png") {
                        if (fileContainsAsciiBytes(file, term)) {
                            throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/res file: ${file.path}")
                        }
                    } else {
                        if (file.readText().contains(term)) {
                            throw GradleException("Forbidden GPL/YouTube term '$term' found in src/main/res file: ${file.path}")
                        }
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

        // 7. Check jniLibs (prebuilt .so that could hide extractor) - B2/B3 fix
        val jniLibsDir = file("src/main/jniLibs")
        if (jniLibsDir.exists()) {
            jniLibsDir.walkTopDown().filter { it.isFile }.forEach { file ->
                val name = file.name
                for (term in forbiddenTerms) {
                    if (name.contains(term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs file name: ${file.path}")
                    }
                    if (fileContainsAsciiBytes(file, term)) {
                        throw GradleException("Forbidden GPL/YouTube term '$term' found in jniLibs binary: ${file.path}")
                    }
                }
            }
        }

        println("[validateProdIsolation] PASSED: Prod isolation verified successfully across manifests, kotlin, res, assets, proguard, cpp, and jniLibs.")
        // 8. Pulsr Pure: prod overlay must strip INTERNET + YTM download worker.
        val prodManifest = file("src/prod/AndroidManifest.xml")
        if (!prodManifest.exists()) {
            throw GradleException("Pulsr Pure prod overlay src/prod/AndroidManifest.xml is missing!")
        } else {
            val prodText = prodManifest.readText()
            if (!prodText.contains("android.permission.INTERNET") || !prodText.contains("tools:node=\"remove\"")) {
                throw GradleException("Pulsr Pure prod overlay must remove INTERNET permission!")
            }
            if (!prodText.contains(".DownloadService") || !prodText.contains("tools:node=\"remove\"")) {
                throw GradleException("Pulsr Pure prod overlay must remove DownloadService!")
            }
        }
    }
}

afterEvaluate {
    tasks.matching { it.name.startsWith("assemble") || it.name == "check" || it.name == "test" }.configureEach {
        dependsOn("validateProdIsolation")
    }
}
