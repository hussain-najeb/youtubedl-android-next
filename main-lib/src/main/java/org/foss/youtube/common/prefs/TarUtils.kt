package org.foss.youtube.common.prefs

import android.system.Os
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.io.IOUtils

object Unpack {
    fun untarXz(sourceFile: File, targetDirectory: File) {
        val targetRoot = targetDirectory.canonicalFile

        fun isInside(file: File): Boolean =
            file.canonicalPath == targetRoot.path ||
                file.canonicalPath.startsWith(targetRoot.canonicalPath + File.separator)

        BufferedInputStream(FileInputStream(sourceFile)).use { buffered ->
            XZCompressorInputStream(buffered).use { xzIn ->
                TarArchiveInputStream(xzIn).use { tarIn ->
                    while (true) {
                        val entry = tarIn.nextEntry ?: break
                        val destination = File(targetRoot, entry.name)
                        // prevent path traversal (tarSlip)
                        if (!isInside(destination)) {
                            throw SecurityException("Entry is outside of the target dir: ${entry.name}")
                        }

                        when {
                            entry.isDirectory -> destination.mkdirs()

                            entry.isSymbolicLink -> {
                                val target = entry.linkName
                                val resolve = File(destination.parentFile, target)
                                if (!isInside(resolve)) {
                                    throw SecurityException("Entry is outside of the target dir: ${entry.name}")
                                }

                                destination.parentFile?.mkdirs()
                                destination.delete()
                                Os.symlink(target, destination.absolutePath)
                            }

                            entry.isLink -> {
                                val resolve = File(targetRoot, entry.linkName)
                                if (!isInside(resolve)) {
                                    throw SecurityException("Entry is outside of the target dir: ${entry.name}")
                                }

                                destination.parentFile?.mkdirs()
                                destination.delete()
                                Os.link(resolve.absolutePath, destination.absolutePath)
                            }

                            else -> {
                                destination.parentFile?.mkdirs()
                                FileOutputStream(destination).use { outputStream ->
                                    IOUtils.copy(tarIn, outputStream)
                                }
                                if (entry.mode != 0) {
                                    Os.chmod(destination.absolutePath, entry.mode and 0b111111111)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
