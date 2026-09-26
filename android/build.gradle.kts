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
    // Align every plugin with the app's compileSdk (AAR metadata checks).
    // Registered BEFORE evaluationDependsOn (which evaluates :app immediately).
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val m = androidExt.javaClass.getMethod(
                    "setCompileSdk", Integer.TYPE
                )
                m.invoke(androidExt, 36)
            } catch (_: Exception) {
            }
            try {
                val lint = androidExt.javaClass.methods
                    .firstOrNull { it.name == "getLint" }
                    ?.invoke(androidExt)
                if (lint != null) {
                    lint.javaClass.methods
                        .firstOrNull { it.name == "setCheckReleaseBuilds" }
                        ?.invoke(lint, false)
                }
            } catch (_: Exception) {
            }
        }
    }
}

subprojects {
    // Force plugin buildscript classpaths onto versions already resolved by
    // the app module — avoids downloading multiple AGP/KGP versions.
    buildscript {
        repositories {
            google()
            mavenCentral()
        }
        configurations.classpath {
            resolutionStrategy {
                force("com.android.tools.build:gradle:9.1.0")
                force("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.0")
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
