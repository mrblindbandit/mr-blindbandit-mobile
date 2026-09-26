import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun local(key: String, default: String = "") = (localProps.getProperty(key) ?: default).replace("\"", "\\\"")

// Client-safe production identifiers/endpoints only. Never place reusable server credentials here.
val productionClerkPublishableKey = "pk_live_Y2xlcmsubXJibGluZGJhbmRpdC5uZXQk"
val productionLiveKitUrl = "wss://mrblindbandit-net-bpd8we2l.livekit.cloud"
val productionGoogleOAuthClientId = "734579493984-oiet9j1hv9lhp7rkcjs9cqhf02biuatg.apps.googleusercontent.com"

android {
    namespace = "net.mrblindbandit.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "net.mrblindbandit.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 7
        versionName = "1.7.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField("String", "WEB_BASE_URL", "\"https://mrblindbandit.net\"")
        buildConfigField("String", "API_BASE_URL", "\"https://api.mrblindbandit.net\"")
        buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"${local("CLERK_PUBLISHABLE_KEY", productionClerkPublishableKey)}\"")
        buildConfigField("String", "LIVEKIT_URL", "\"${local("LIVEKIT_URL", productionLiveKitUrl)}\"")
        buildConfigField("String", "GOOGLE_OAUTH_CLIENT_ID", "\"${local("GOOGLE_OAUTH_CLIENT_ID", productionGoogleOAuthClientId)}\"")
    }

    // Release signing is read from the environment (GitHub Actions secrets) or local.properties.
    // Keystores and passwords are never committed. Without them, bundleRelease produces an
    // unsigned AAB that Play App Signing can still accept after upload-key signing.
    val releaseStoreFile = System.getenv("ANDROID_KEYSTORE_PATH") ?: local("ANDROID_KEYSTORE_PATH")
    val hasReleaseSigning = releaseStoreFile.isNotBlank() && rootProject.file(releaseStoreFile).exists()
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: local("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: local("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: local("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isDebuggable = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += setOf(
            "/META-INF/{AL2.0,LGPL2.1}",
            "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            "META-INF/versions/**/OSGI-INF/MANIFEST.MF",
        )
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        checkDependencies = false
        abortOnError = true
        checkReleaseBuilds = true
        warningsAsErrors = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

configurations.configureEach {
    resolutionStrategy {
        force("com.squareup.okhttp3:okhttp:5.3.2")
        force("com.squareup.okhttp3:okhttp-android:5.3.2")
        force("com.squareup.okhttp3:logging-interceptor:5.3.2")
        force("com.jakewharton.timber:timber:5.0.1")
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.12.01"))

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.core:core-splashscreen:1.0.1")

    // Clerk authentication. Only the publishable key ships in the client.
    implementation("com.clerk:clerk-android-api:1.0.33")

    // LiveKit realtime. Room tokens are obtained from the authenticated Blindbandit API.
    implementation("io.livekit:livekit-android:2.18.3")

    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
    implementation("com.google.firebase:firebase-messaging")

    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("org.robolectric:robolectric:4.14.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
