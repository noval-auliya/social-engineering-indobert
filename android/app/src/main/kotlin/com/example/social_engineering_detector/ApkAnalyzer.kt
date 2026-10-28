package com.example.social_engineering_detector

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.zip.ZipFile

/**
 * Ekstraksi fitur statis dari file APK (APK tidak dipasang / dijalankan).
 *
 * Fitur harus sama dengan ml/malware/evaluate_apk.py:
 *  - izin dari manifest, panggilan API dari tabel method_ids di classes*.dex,
 *  - flags: accessibility_service, notification_listener, device_admin,
 *    hidden_dex, debug_cert,
 *  - SHA-256 file dan sertifikat penanda tangan.
 */
object ApkAnalyzer {
    private val ROOT_DEX = Regex("^classes\\d*\\.dex$")
    private val FLAG_BY_PERMISSION = mapOf(
        "android.permission.BIND_ACCESSIBILITY_SERVICE" to "accessibility_service",
        "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE" to "notification_listener",
        "android.permission.BIND_DEVICE_ADMIN" to "device_admin",
    )

    /** [source] = path file atau URI content:// dari file picker. */
    fun analyze(context: Context, source: String, apiFeatures: List<String>): Map<String, Any?> {
        val uri = Uri.parse(source)
        if (uri.scheme == "content") {
            val tmp = File.createTempFile("scan_", ".apk", context.cacheDir)
            try {
                context.contentResolver.openInputStream(uri)!!.use { input ->
                    tmp.outputStream().use { input.copyTo(it) }
                }
                return analyzeFile(context, tmp, apiFeatures)
            } finally {
                tmp.delete()
            }
        }
        return analyzeFile(context, File(uri.path ?: source), apiFeatures)
    }

    private fun analyzeFile(context: Context, file: File, apiFeatures: List<String>): Map<String, Any?> {
        val pm = context.packageManager
        val info = archiveInfo(pm, file.path)
            ?: throw IllegalArgumentException("Bukan file APK yang valid")

        val permissions = info.requestedPermissions?.toList().orEmpty()
        val flags = mutableSetOf<String>()
        val protectedBy = (info.services.orEmpty().map { it.permission } +
            info.receivers.orEmpty().map { it.permission })
        for (p in protectedBy) FLAG_BY_PERMISSION[p]?.let(flags::add)

        val wantedClasses = apiFeatures.map { it.substringBefore("->") }.toSet()
        val apis = mutableSetOf<String>()
        var dexCount = 0
        ZipFile(file).use { zip ->
            for (entry in zip.entries()) {
                val name = entry.name
                if (ROOT_DEX.matches(name)) {
                    dexCount++
                    val bytes = zip.getInputStream(entry).use { it.readBytes() }
                    apis += dexMethodRefs(bytes, wantedClasses)
                } else if (name.endsWith(".dex") || name.endsWith(".jar")) {
                    flags += "hidden_dex"
                }
            }
        }

        val certs = signerCertificates(info)
        if (certs.any { it.subjectX500Principal.name.contains("CN=Android Debug") }) {
            flags += "debug_cert"
        }

        info.applicationInfo?.apply {
            sourceDir = file.path
            publicSourceDir = file.path
        }
        return mapOf(
            "package" to info.packageName,
            "appName" to info.applicationInfo?.loadLabel(pm)?.toString(),
            "versionName" to info.versionName,
            "versionCode" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else
                @Suppress("DEPRECATION") info.versionCode.toLong(),
            "fileSize" to file.length(),
            "sha256" to sha256(file),
            "permissions" to permissions,
            "apis" to apis.intersect(apiFeatures.toSet()).sorted(),
            "flags" to flags.sorted(),
            "certSha256" to certs.map { hex(MessageDigest.getInstance("SHA-256").digest(it.encoded)) },
            "certSubject" to certs.firstOrNull()?.subjectX500Principal?.name,
            "dexCount" to dexCount,
            "activityCount" to (info.activities?.size ?: 0),
            "serviceCount" to (info.services?.size ?: 0),
            "receiverCount" to (info.receivers?.size ?: 0),
        )
    }

    private fun archiveInfo(pm: PackageManager, path: String): PackageInfo? {
        var flags = PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES or
            PackageManager.GET_RECEIVERS or PackageManager.GET_ACTIVITIES
        flags = flags or if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
        else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        return pm.getPackageArchiveInfo(path, flags)
    }

    private fun signerCertificates(info: PackageInfo): List<X509Certificate> {
        val sigs = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION") info.signatures
        } ?: return emptyList()
        val cf = CertificateFactory.getInstance("X.509")
        return sigs.mapNotNull {
            runCatching { cf.generateCertificate(it.toByteArray().inputStream()) as X509Certificate }
                .getOrNull()
        }
    }

    /** "Lkelas;->metode" untuk method_ids yang kelasnya termasuk [wanted]. */
    internal fun dexMethodRefs(dex: ByteArray, wanted: Set<String>): Set<String> {
        val buf = ByteBuffer.wrap(dex).order(ByteOrder.LITTLE_ENDIAN)
        val strOff = buf.getInt(0x3C)
        val typeOff = buf.getInt(0x44)
        val methSize = buf.getInt(0x58)
        val methOff = buf.getInt(0x5C)
        val cache = HashMap<Int, String>()

        fun string(idx: Int): String = cache.getOrPut(idx) {
            var pos = buf.getInt(strOff + 4 * idx)
            while (dex[pos].toInt() and 0x80 != 0) pos++ // lewati panjang (uleb128)
            pos++
            var end = pos
            while (dex[end].toInt() != 0) end++
            String(dex, pos, end - pos, Charsets.UTF_8)
        }

        val refs = HashSet<String>()
        for (i in 0 until methSize) {
            val base = methOff + 8 * i
            val classIdx = buf.getShort(base).toInt() and 0xFFFF
            val cls = string(buf.getInt(typeOff + 4 * classIdx))
            if (cls in wanted) refs += "$cls->${string(buf.getInt(base + 4))}"
        }
        return refs
    }

    private fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val chunk = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                md.update(chunk, 0, n)
            }
        }
        return hex(md.digest())
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}
