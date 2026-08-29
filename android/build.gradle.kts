import org.gradle.api.tasks.compile.JavaCompile

/**
 * Pulsr Music - Root Build Configuration
 *
 * Requirements:
 * - Android Gradle Plugin (AGP): 9.0.1+
 * - Gradle: 8.11+ / 9.0+
 * - Kotlin: 2.0+ (JVM Target 17)
 * - Java / JDK: 17
 */

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (android != null) {
            if (android.namespace.isNullOrEmpty()) {
                android.namespace = when (project.name) {
                    "on_audio_query_android" -> "com.lucasjosino.on_audio_query"
                    else -> "com.example.${project.name.replace('-', '_').replace(':', '_')}"
                }
            }
            android.compileSdk = 36
        }
    }
}

// JVM 17 + Kotlin language 2.0 alignment: plugin modules (home_widget, sentry_flutter,
// on_audio_query_android, ...) pin Java 1.8 / old Kotlin in their own build.gradle while
// AGP 9 defaults Kotlin to JVM 17 -> the AGP 9 Java/Kotlin consistency check fails.
//
// Ordering: the plugin's build.gradle runs during ITS evaluation and would overwrite any
// DSL value set before it. afterEvaluate runs after evaluation -> final DSL win.
// :app is force-evaluated early (evaluationDependsOn) and already sets 17 itself, so skipped.
subprojects {
    if (project.name == "app") return@subprojects

    fun applyJvmAlignment(project: Project) {
        project.plugins.withId("com.android.library") {
            project.extensions
                .findByType(com.android.build.gradle.LibraryExtension::class.java)
                ?.compileOptions?.apply {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
        }
        project.plugins.withId("com.android.application") {
            project.extensions
                .findByType(com.android.build.gradle.AppExtension::class.java)
                ?.compileOptions?.apply {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
        }
        project.tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    // Old plugins (on_audio_query pins Kotlin 1.6.10) would otherwise
                    // compile with language 1.6, which KGP 2.3+ rejects.
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
                    apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
                }
            }
    }

    if (project.state.executed) {
        applyJvmAlignment(project)
    } else {
        project.afterEvaluate { applyJvmAlignment(project) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
