allprojects {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

//added while setting up the firebase
// buildscript {
//     dependencies {
//         classpath("com.google.gms:google-services:4.3.15")
//     }
// }
plugins {
  // ...
  // Add the dependency for the Google services Gradle plugin
    id("com.google.gms.google-services") version "4.4.3" apply false

}

