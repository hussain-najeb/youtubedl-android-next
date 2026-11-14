Welcome to the build documentation of **YoutubeDL-Android Next**! 

This document will teach you what the *build.tar.gz* does and how to build all the components this library has.


## Components
The build folder has all the components you need to use in this library, from *libcffi* to checking the stack on your own phone.

The folder has a bunch of steps, all of which will be explained.

#### 00-setup-toolchains.sh

This script prepares the entire **Android** cross-compilation environment, and it is the first script that must run. You don't need to run it manually however, as `build-all.sh` does that automatically.

The script downloads (or updates) the pinned **Termux** packages repository, applies the custom **Termux** patches on top of it, then prepares the **Android NDK**. It also checks that **Java**, **Docker**, **CMake**, **Ninja** and the other dependencies are available, installs the required **Python** build tools, and downloads the pinned **Termux Docker** builder image. Finally, it records every build version and its provenance in `out/build-provenance.env`.


#### 10-build-libffi.sh

This script builds **libffi**, a C library that provides foreign-function calling capabilities, and it is what **CFFI** depends on to work.

The script builds the **Termux** `libffi` package for every ABI, then extracts the generated `.deb` packages. Each result is checked for the correct **ELF** architecture and shared-library SONAME, and after that the headers and libraries are prepared for **CFFI**. Its output is used by `20-build-cffi.sh`.


#### 20-build-cffi.sh

This script builds **CFFI**, the **Python** package that allows Python code to call native C libraries.

The script downloads a pinned **CFFI** source release and verifies its SHA-256 checksum, then patches the build configuration so it uses the **libffi** compiled in stage 10. Android wheels are built for the supported architectures, with a **Termux** cross-build fallback for the 32-bit ones. Finally, **libffi** is bundled into the **CFFI** package and its runtime library search path is fixed, so the package finds it once it's inside your app. Its output is injected into the **Python** runtime later, in stage 50.


#### 30-build-curl-impersonate.sh

This script compiles **Curl-Impersonate**, which provides curl-based HTTP clients that can imitate browser TLS and HTTP fingerprints.

The script downloads a pinned source commit, then cross-compiles the native library for **Android** using **CMake** and the **Android NDK**. The library is built as static libraries, and the script then collects the headers and all the dependent static libraries along with it. The result is used by stage 40.


#### 40-build-curl-cffi.sh

As the name suggests, this builds **Curl-Cffi**. This is particularly important for **yt-dlp** because it provides browser-like HTTP requests and TLS fingerprint impersonation.

The script downloads and checks out the pinned **curl_cffi** source, then modifies its build process to include the **Curl-Impersonate** static dependencies from stage 30. Android **Python** wheels are built for the supported 64-bit architectures, while the 32-bit architectures use **Termux** package builds instead. The resulting wheels or packaged **Python** modules are then published, and stage 50 installs the result into **Python**.


#### 50-build-python.sh

This is a big one, it builds and packages the actual Android Python runtime, as it is a **core runtime**

The script itself builds **Termux Python 3.14.10** for arm32, arm64, and x86_64 then extracts **Python** and its required dependencies to install **CFFI**, **Curl-Cffi**, **Mutagen**, and **Certifi** and its CA certificates, the script also fixes Python native extensions to locate the correct shared libraries.

The script also relocates **Termux-specific ELF** library paths because the **Python** runtime is built using **Termux**, but ultimately runs inside an **Android** application, not inside the **Termux** app. As well as packages the **Python** environment into a ZIP archive for convenience.

The final output should consist of two components, `libpython.so`, which is the **Python** interpreter launcher and `libpython.zip.so`, the packaged Python runtime, standard libraries and site-packages. Together, these provide the Python environment required by the library to work its magic.


#### 60-build-ffmpeg.sh

This script builds **ffmpeg** and **ffprobe** for **Android**. The script is configured a lot to account for **Android** and all the additional libraries mentioned in the [README](https://github.com/hussain-najeb/youtubedl-android-next/blob/master/README.md). 

The process of building ffmpeg itself is done by the excellent project [**ffmpeg-android-maker**](https://github.com/Javernaut/ffmpeg-android-maker) for compiling the necessary `.so` file for **ffmpeg** to work on android with the `-enable-all-free` flag, as to have a complete **ffmpeg** with support for a wide range of software.

The script itself however rips out the mbedtls build script and replaces it with a new one, since ffmpeg was having issues with **clang 21** that shipped with **Termux r30 NDK**, and even harmless warnings were terminating the compilation step as if the warnings were **fatal**, so as to keep the compilation alive, they were turned off, after that, your ffmpeg build should be consistent

> [!NOTE]
> Most compiled libraries are pinned to a specific version as to be as stable as possible, in case of upgrading, move each pinned component in the script to its newest counterpart, thank you.


#### 70-build-quickjs.sh

This builds **QuickJS-ng**... that's it, seriously, this script only downloads a pinned source commit, **cross-compiles** it with **CMake** and **Ninja**, produce the **QuickJS** shared library with the CLI tool and finally configures the executable's runtime library path.

The pinned commit is for version `0.18.0` of the library, the output is predictably `libqjs.so` and `libqjs-cli.so`.


#### 80-build-aria2.sh

This script is for building **Aria2-Next**.

What the script does is that it installs a custom **Termux** package recipe, since the package (**Aria2-Next**) doesn't exist in **termux-packages**. Then, it applies an android multi-architecture patch, since the upstream project doesn't have support for all **Android** ABI's, but only for one ABI, **Android ARM64**, so there were **cross-compilation** effort to bring it to arm32, arm64, and x86_64, then bundles the required C++ runtime, collects its shared libraries, collects CA certificates for HTTPS connections, creates a shell wrapper that configures `LD_LIBRARY_PATH` and `PREFIX`, which only means the shell wrapper makes `aria2-next` behave as though it is running inside a small, self-contained Termux environment, even though it is actually running inside an **Android** application, to then package everything into a ZIP runtime.


The final runtime ZIP contains the executable, wrapper, libraries and TLS certificates.


#### 90-install-payloads.sh

This is the final-ish step, as it combines all previously built components into an Android Gradle project, it copies **Python** and **QuickJS-NG** into the module's jniLibs (`natives`), copies **ffmpeg** and **ffprobe** and package them in a ZIP archive and that includes `libc++_shared.so`, installs the aria2 runtime ZIP and native executable, removes stale native libraries from previous builds, runs Gradle clean, builds the release AAR, checks that all expected ABI libraries exist inside the AAR. 

And this is the final build and packaging stage.


#### 95-verify-payloads.sh

This script tests the compiled artifacts on a connected **Android** device through **ADB**. It is a verification script, not a compilation script, so nothing gets built here.

The script first identifies the device's architecture, then tests the **QuickJS** executable, followed by **ffmpeg** and **ffprobe**, including a check that **ffmpeg** has HTTPS/TLS protocol support. After that, it tests **aria2** and verifies that it can download a real HTTPS resource, and it inspects some **ELF** properties of the binaries. Finally, it provides instructions for the final **yt-dlp** integration test, which is the one step you run yourself.


## Supporting Files
Not everything in the folder is a numbered build stage. These files aren't stages themselves, but the numbered scripts rely on them.

#### common.sh

This is the central configuration file, and the most important one here. Without it, most of the numbered scripts cannot work.

It defines the repository locations, the **Android NDK** locations, the **Java** configuration, the API level (currently 24), the target architectures, every pinned source version and commit, the **Docker** image and its build configuration, and the runtime output locations. It also holds the shared helpers: the ABI conversion functions, **Python** version detection, the **Termux** package build functions, and the **ELF** RUNPATH relocation and verification.


#### build-all.sh

This script runs all the build stages sequentially, from 00 through 90. It builds every ABI in the configured `ABIS` list, and it doesn't run stage 95, so device verification is something you do manually afterwards.


#### dev-run.sh

This is the development runner, meant for when you don't want to rebuild everything. It supports selecting a single ABI and a stage range, and it can produce detailed logs and tracing, as well as run stage 95 for you.

They serve different purposes, so here is how the two runners compare:

| Feature             | build-all.sh             | dev-run.sh       |
| :------------------ | :----------------------- | :--------------- |
| Full build          | Yes                      | Yes              |
| Individual ABI      | No, uses configured ABIS | Yes              |
| Select stage range  | No                       | Yes              |
| Detailed tracing    | No                       | Yes              |
| Main log file       | No                       | Yes              |
| Device verification | Manual                   | Can run stage 95 |

For example, this runs only **ffmpeg** for ARM64:

```bash
./dev-run.sh arm64-v8a 60 60
```

And this runs stages 50 through 70 (**Python**, **ffmpeg** and **QuickJS**) for ARM64:

```bash
./dev-run.sh arm64-v8a 50 70
```


#### apply-termux-patches.sh

This script applies the custom patches to the **Termux** packages repository. The patches themselves are listed in the `patches/termux/` section below.

## Folders
Besides the scripts, the folder has two subfolders.

#### aria2-next/

This folder contains the custom **Termux** build recipe for **Aria2-Next**, which is what stage 80 installs, since the package doesn't exist in **termux-packages**.

`build.sh` defines how **Termux** downloads, checks out, builds and installs **Aria2-Next**, while `0001-android-multi-arch.patch` adjusts the **OpenSSL** target selection so it works for arm32, arm64, and x86_64 **Android** builds.


#### patches/termux/

This folder contains five modifications to the upstream **Termux** packages repository:

| Patch                                               | What it does                                                                       |
| :-------------------------------------------------- | :--------------------------------------------------------------------------------- |
| `0001-fermux-materialize-ndk-toolchain.patch`       | Adjusts Termux's NDK toolchain setup, removing its `fuse-overlayfs` mounting path. |
| `0002-fermux-xcb-proto-target-python-cleanup.patch` | Corrects Python bytecode cleanup in the `xcb-proto` package build.                 |
| `0003-fermux-host-python-preserve-path.patch`       | Preserves the host executable `PATH` during a Python build installation.           |
| `0004-fermux-python-skip-autoreconf.patch`          | Prevents an unnecessary `autoreconf` invocation during Termux Python compilation.  |
| `0005-fermux-libxml2-disable-docs.patch`            | Disables `libxml2` documentation generation and removes unnecessary build dependencies. |


> [!NOTE]
> The exact directory locations can be overridden using environment variables.


## What The Final Application Receives
The purpose of this entire system is to produce these runtime components:

| Output             | Purpose                                         |
| :----------------- | :---------------------------------------------- |
| `libpython.so`     | **Python** interpreter launcher                 |
| `libpython.zip.so` | **Python** standard library and modules         |
| `libqjs.so`        | **QuickJS** JavaScript engine                   |
| `libqjs-cli.so`    | **QuickJS** executable                          |
| `libffmpeg.so`     | **ffmpeg** executable                           |
| `libffprobe.so`    | **ffprobe** executable                          |
| `libffmpeg.zip.so` | **ffmpeg** dependency libraries and C++ runtime |
| `libaria2c.so`     | **aria2** executable                            |
| `libaria2.zip.so`  | **aria2** runtime libraries and certificates    |

These are packaged into the release AAR under `jni/<ABI>/`.
