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

android {
    namespace = "net.mrblindbandit.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "net.mrblindbandit.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 5
        versionName = "1.5.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField("String", "WEB_BASE_URL", "\"https://mrblindbandit.net\"")
        buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"${local("CLERK_PUBLISHABLE_KEY")}\"")
        buildConfigField("String", "LIVEKIT_URL", "\"${local("LIVEKIT_URL")}\"")
        buildConfigField("String", "LIVEKIT_SCAFFOLD_TOKEN", "\"${local("LIVEKIT_SCAFFOLD_TOKEN")}\"")
        buildConfigField("String", "GOOGLE_OAUTH_CLIENT_ID", "\"${local("GOOGLE_OAUTH_CLIENT_ID")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}


// Clerk 1.0.33 pulls browser 1.10 / okhttp-android 5.4 (need compileSdk 36 + AGP ≥ 8.9.1).
// Prefer AGP 8.9 + SDK 36 when CI can edit workflows (`workflow` scope); until then force SDK-35-safe deps.
configurations.configureEach {
    resolutionStrategy {
        force("androidx.browser:browser:1.8.0")
        force("com.squareup.okhttp3:okhttp:5.3.2")
        force("com.squareup.okhttp3:okhttp-android:5.3.2")
        force("com.squareup.okhttp3:logging-interceptor:5.3.2")
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

    // Clerk (publishable key only in client)
    implementation("com.clerk:clerk-android-api:1.0.33")

    // LiveKit realtime (tokens from server; scaffold token via local.properties only)
    implementation("io.livekit:livekit-android:2.18.3")

    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
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
