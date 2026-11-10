package org.foss.youtube.common.prefs

import android.system.Os
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.io.IOUtils
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets

object Unpack {
    fun unzip(sourceFile: File, targetDirectory: File) {
        val targetRoot = targetDirectory.canonicalFile

        fun isInside(file: File): Boolean =
            file.canonicalPath == targetRoot.path ||
                 file.canonicalPath.startsWith(targetRoot.canonicalPath + File.separator)

        ZipFile.builder().setFile(sourceFile).get().use { zipFile ->
            val entries = zipFile.entries
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                val destination = File(targetRoot, entry.name)
                // prevent zipSlip
                if (!isInside(destination)) throw SecurityException(("Entry is outside of the target dir: ${entry.name}"))

                when {
                    entry.isDirectory -> destination.mkdirs()

                    entry.isUnixSymlink -> {
                        val target = zipFile.getInputStream(entry).use {
                            IOUtils.toString(it, StandardCharsets.UTF_8)
                        }
                        val resolve = File(destination.parentFile, target)
                        if (!isInside(resolve)) throw SecurityException(("Entry is outside of the target dir: ${entry.name}"))

                        destination.parentFile?.mkdirs()
                        destination.delete()
                        Os.symlink(target, destination.absolutePath)

                    }

                    else -> {
                        destination.parentFile?.mkdirs()
                        zipFile.getInputStream(entry).use { inputStream ->
                            FileOutputStream(destination).use { outputStream ->
                                IOUtils.copy(inputStream, outputStream)
                            }
                        }
                        if (entry.unixMode != 0) {
                            Os.chmod(destination.absolutePath, entry.unixMode and 0b111111111)
                        }
                    }
                }
            }
        }
    }
}