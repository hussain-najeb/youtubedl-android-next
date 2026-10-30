## Overview

**YouTubeDL-Android Next** is a modern fork of [youtubedl-android](https://github.com/yausername/youtubedl-android). It updates the runtime and underlying libraries while introducing additional features and improvements.

## Improvements

### Download Process Management

- Introduces a more robust system for managing download processes.

### Updated FFmpeg

- Updates FFmpeg to version **9.0.2**.

### QuickJS-NG

- Replaces [QuickJS](https://bellard.org/quickjs/) with [QuickJS-NG](https://github.com/quickjs-ng/quickjs), a maintained fork of the original QuickJS project.

### Aria2-Next

- Replaces [Aria2c](https://github.com/aria2/aria2) with [Aria2-Next](https://github.com/AnInsomniacy/aria2-next), a modern fork that introduces additional security features, bug fixes, and performance improvements.

## New Features

### curl_cffi Integration

Adds [curl_cffi](https://github.com/lexiforest/curl_cffi), an HTTP client that supports browser impersonation by reproducing browser TLS, JA3, and HTTP/2 fingerprints.

### curl-impersonate for Android

Integrates [curl-impersonate](https://github.com/lexiforest/curl-impersonate) to bring browser impersonation support to Android.

The integration includes cross-compilation support for Android ABIs, including **x86** and **armeabi-v7a**, extending support beyond the previously available architectures.

This is particularly useful because websites such as TikTok, Instagram, and YouTube increasingly use TLS-based protections and other mechanisms that can make automated requests more difficult.

By integrating curl-impersonate with [yt-dlp](https://github.com/yt-dlp/yt-dlp), the project aims to provide more consistent request compatibility across supported Android architectures.

It can also be used alongside Aria2-Next and QuickJS-NG to provide a more capable downloading runtime.

## Library Versions

| Library | Version |
|---|---:|
| QuickJS-NG | 0.17.0 |
| Aria2-Next | 3.0.9 |
| FFmpeg | 9.0.2 |
| Python | 3.14 |
| yt-dlp | 2026.10.26 |

## Documentation and Build Scripts

You do not need to inspect the build scripts to use the project. However, if you are interested in how the native components are built for the supported Android ABIs, you can review the [Build Documentation](Build-all.md).

If you encounter an issue with any of the build scripts, please report it so that it can be investigated and corrected.

