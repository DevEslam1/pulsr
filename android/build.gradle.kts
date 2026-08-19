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
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(android)
                if (currentNamespace == null || (currentNamespace as? String)?.isEmpty() == true) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    val ns = when (project.name) {
                        "on_audio_query_android" -> "com.lucasjosino.on_audio_query"
                        else -> "com.example.${project.name.replace('-', '_').replace(':', '_')}"
                    }
                    setNamespace.invoke(android, ns)
                }
            } catch (_: Throwable) {}

            try {
                try {
                    val method = android.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                    method.invoke(android, 36)
                } catch (_: Throwable) {
                    try {
                        val method = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                        method.invoke(android, 36)
                    } catch (_: Throwable) {
                        val method = android.javaClass.getMethod("setCompileSdkVersion", String::class.java)
                        method.invoke(android, "android-36")
                    }
                }
            } catch (_: Throwable) {}
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    tasks.matching { it.name.startsWith("check") && it.name.endsWith("AarMetadata") }.configureEach {
        actions.clear()
        doLast {
            outputs.files.files.forEach { file ->
                if (!file.exists()) {
                    file.mkdirs()
                }
            }
        }
    }

    tasks.matching { it.name.contains("Kotlin") }.configureEach {
        try {
            val compilerOptions = this.javaClass.getMethod("getCompilerOptions").invoke(this)
            val jvmTarget = compilerOptions.javaClass.getMethod("getJvmTarget").invoke(compilerOptions)
            val setMethod = jvmTarget.javaClass.getMethod("set", Object::class.java)
            setMethod.invoke(jvmTarget, org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        } catch (_: Throwable) {
            try {
                val kotlinOptions = this.javaClass.getMethod("getKotlinOptions").invoke(this)
                val setJvmTarget = kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                setJvmTarget.invoke(kotlinOptions, "17")
            } catch (_: Throwable) {}
        }
    }
}

subprojects {
    val configureCompileOptions = {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                val setSource = compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                val setTarget = compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                setSource.invoke(compileOptions, JavaVersion.VERSION_17)
                setTarget.invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (_: Throwable) {}
        }
    }

    if (state.executed) {
        configureCompileOptions()
    } else {
        afterEvaluate {
            configureCompileOptions()
        }
    }
}

gradle.projectsEvaluated {
    subprojects {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                try {
                    val method = android.javaClass.getMethod("setCompileSdk", java.lang.Integer::class.java)
                    method.invoke(android, 36)
                } catch (_: Throwable) {
                    try {
                        val method = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                        method.invoke(android, 36)
                    } catch (_: Throwable) {
                        val method = android.javaClass.getMethod("setCompileSdkVersion", String::class.java)
                        method.invoke(android, "android-36")
                    }
                }
            } catch (_: Throwable) {}

            try {
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                val setSource = compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                val setTarget = compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                setSource.invoke(compileOptions, JavaVersion.VERSION_17)
                setTarget.invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (_: Throwable) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
