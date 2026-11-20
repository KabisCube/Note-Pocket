import java.util.Properties

plugins {
	id("com.android.application")
	id("dev.flutter.flutter-gradle-plugin")
}

val keystoreFile = rootProject.file("../signing/keystore.properties")
val keystoreProperties = Properties()
if (keystoreFile.exists()) keystoreFile.inputStream().use { keystoreProperties.load(it) }

android {
	namespace = "com.notepocket.app"
	compileSdk = flutter.compileSdkVersion
	ndkVersion = flutter.ndkVersion

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}

	defaultConfig {
		applicationId = "com.notepocket.app"
		minSdk = flutter.minSdkVersion
		targetSdk = flutter.targetSdkVersion
		versionCode = flutter.versionCode
		versionName = flutter.versionName
	}

	signingConfigs {
		create("release") {
			if (keystoreFile.exists()) {
				storeFile = File(keystoreFile.parentFile, keystoreProperties.getProperty("storeFile"))
				storePassword = keystoreProperties.getProperty("storePassword")
				keyAlias = keystoreProperties.getProperty("keyAlias")
				keyPassword = keystoreProperties.getProperty("keyPassword")
			}
		}
	}

	buildTypes {
		release {
			signingConfig = signingConfigs.getByName(if (keystoreFile.exists()) "release" else "debug")
		}
	}

	dependenciesInfo {
		includeInApk = false
		includeInBundle = false
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
