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

// Enforce JVM 17 for Java and Kotlin — fixes :home_widget 1.8 vs 17 (AGP 9 + KGP)
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
            apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
        }
    }
}

// tasks.withType handles any late-created JavaCompile tasks that escape the DSL above
// (kept for completeness; the android.compileOptions fix above is primary).

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
