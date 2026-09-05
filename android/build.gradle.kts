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
    if (project.projectDir.toPath().root == rootProject.projectDir.toPath().root) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Subproject configuration for Flutter Android library plugins
// FIX: Inconsistent JVM Target 1.8 vs 17 on :home_widget (and other KGP plugins)
// Root cause: plugin's own android.compileOptions defaults to 1.8, while Kotlin targets 17.
// We force 17 via android DSL + toolchain so Java and Kotlin match (AGP 9 + Kotlin 2.3 + JDK 17).
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
        if (android != null) {
            if (android.namespace.isNullOrEmpty()) {
                android.namespace = when (project.name) {
                    "on_audio_query_android" -> "com.lucasjosino.on_audio_query"
                    else -> "com.example.${project.name.replace('-', '_').replace(':', '_')}"
                }
            }
            android.compileSdk = 37
        }
    }
}
// Force Java 17 for all Android library/app projects after they are evaluated.
// Using gradle.afterProject avoids the "already evaluated" error from Project.afterEvaluate
// when subprojects have already been configured.
gradle.afterProject {
    val android = extensions.findByName("android")
    if (android is com.android.build.api.dsl.CommonExtension) {
        android.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
        android.compileOptions.targetCompatibility = JavaVersion.VERSION_17
    }
}

// Enforce JVM 17 for Java and Kotlin — fixes :home_widget 1.8 vs 17 (AGP 9 + KGP)
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            // sentry_flutter 8.x pins languageVersion "1.6", which Kotlin 2.3
            // refuses outright. Lift any stale plugin to the 2.0 floor.
            val requested = languageVersion.orNull
            if (requested != null &&
                requested < org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0
            ) {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
            }
        }
    }
}

// tasks.withType handles any late-created JavaCompile tasks that escape the DSL above
// (kept for completeness; the android.compileOptions fix above is primary).

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
