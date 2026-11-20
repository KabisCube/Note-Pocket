package com.notepocket.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val storageChannelName = "note_pocket/storage"
	private val storagePermissionRequestCode = 1

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"hasStorageAccess" -> result.success(hasStorageAccess())
				"requestStorageAccess" -> {
					requestStorageAccess()
					result.success(null)
				}
				"documentsFolder" -> result.success(
					Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).absolutePath
				)
				else -> result.notImplemented()
			}
		}
	}

	private fun hasStorageAccess(): Boolean {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return Environment.isExternalStorageManager()
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
		return checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
	}

	private fun requestStorageAccess() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
			val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
			startActivity(intent)
		} else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), storagePermissionRequestCode)
		}
	}
}
