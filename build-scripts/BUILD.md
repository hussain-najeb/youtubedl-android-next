Welcome to the build documentation of **YoutubeDL-Android Next**! 

This document will teach you what the *build.tar.gz* does and how to build all the components this library has.




## What you need

You need a bunch of software to execute these commands, like having **Java** installed and setting it in your "**.bashrc**" file, I strongly suggest using **Java** 21 from **Termux**!

Also you need docker installed, as its crucial to use, fetch, cross-compile, and do the magic that is needed for the scripts to work, something like:

```
sudo apt install -y docker.io
```

For **Ubuntu** systems, I assume you can replace "apt" with "dnf" for example.

Also the scripts do need a bunch of software that assumes you installed, but just to be safe, here is all the software you need:

```
sudo apt update

sudo apt install -y \
    docker.io \
    git \
    python3 \
    python3-pip \
    python3-venv \
    cmake \
    ninja-build \
    build-essential \
    binutils \
    adb \
    curl \
    coreutils \
    dpkg-dev \
    patchelf \
    meson \
    nasm \
    file \
    zip \
    unzip \
    tar \
    xz-utils \
    pkg-config \
    autoconf \
    automake \
    libtool \
    gettext \
    perl
```

Then you can just copy and paste these commands, run them, and then run the "**./build-all**" script and face no issues (hopefully).

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

The script also relocates **Termux-specific ELF** library paths because the **Python** runtime is built using **Termux**, but ultimately runs inside an **Android** application, not inside the **Termux** app. It deduplicates `curl_cffi`/`cffi` shared libs, strips unused stdlib/dead leftovers, and packages the **Python** environment into a per-ABI BCJ-filtered `tar.xz` archive (`preset=9e, dict=16MiB`).

The final output should consist of two components, `libpython.so`, which is the **Python** interpreter launcher and `libpython.tar.xz.so`, the packaged Python runtime, standard libraries and site-packages. Together, these provide the Python environment required by the library to work its magic.


#### 60-build-ffmpeg.sh

This script builds **ffmpeg** and **ffprobe** for **Android**. The script is configured to account for **Android** and all the additional libraries mentioned in the [README](https://github.com/hussain-najeb/youtubedl-android-next/blob/master/README.md).

The process of building ffmpeg itself is done by the excellent project [**ffmpeg-android-maker**](https://github.com/Javernaut/ffmpeg-android-maker) using an explicit 9-library whitelist (`libdav1d`, `libmp3lame`, `libopus`, `libvpx`, `libwebp`, `libx264`, `libx265`, `libxml2`, `mbedtls`) plus Android **MediaCodec** hardware acceleration (`--enable-jni --enable-mediacodec`). It also applies size optimizations (`-Os`, `--enable-small`, `-ffunction-sections -fdata-sections`, `--gc-sections`, `--icf=safe`, `--pack-dyn-relocs=android`) and switches `libvpx` to `--enable-runtime-cpu-detect` so `arm64-v8a` works cleanly across CPUs without newer SIMD extensions.

The script also replaces the mbedtls build script so **clang 21** (shipped with **Android NDK r30**) does not treat harmless warnings as fatal errors, and links `-lmbedtls -lmbedx509 -lmbedcrypto` explicitly for standalone HTTPS/TLS support. It just works (hopefully).

> [!NOTE]
> Most compiled libraries are pinned to a specific version as to be as stable as possible, in case of upgrading, move each pinned component in the script to its newest counterpart, thank you.


#### 70-build-quickjs.sh

This builds **QuickJS-ng**... that's it, seriously, this script downloads a pinned source commit and **cross-compiles** it with **CMake** and **Ninja** using `-DBUILD_SHARED_LIBS=OFF`, `-Os`, ThinLTO (`-flto=thin`), `--gc-sections`, and `--pack-dyn-relocs=android`.

The pinned commit is for version `0.18.0` of the library; the output is a single standalone statically linked `libqjs-cli.so` executable.


#### 80-build-aria2.sh

This script is for building **Aria2-Next**.

What the script does is that it installs a custom **Termux** package recipe, since the package (**Aria2-Next**) doesn't exist in **termux-packages**. Then, it applies an android multi-architecture patch to cross-compile for arm32, arm64, and x86_64 while dynamically reusing the prebuilt FFmpeg shared libraries from stage 60 and Termux's shared OpenSSL, SQLite, Expat, and zlib, compiling with `-Oz`, ThinLTO across vendored static libs, and `-Dlogging=OFF` on `libtorrent`. It then bundles the executable, wrapper, and TLS certificates into an intermediate ZIP archive for stage 90.


#### 90-install-payloads.sh

This is the final-ish step, as it combines all previously built components into an Android Gradle project: it copies **Python** and standalone **QuickJS-NG** (`libqjs-cli.so`) into the module's `jniLibs` (`natives` and `natives-x86_64`), copies **ffmpeg** and **ffprobe** and packages their shared libraries plus `libc++_shared.so` into a per-ABI BCJ-filtered `libffmpeg.tar.xz.so` archive, installs the native `libaria2c.so` executable, removes stale native libraries from previous builds (including legacy `libqjs.so` and `.zip.so` files), runs Gradle clean, builds the release AARs, and checks that all expected ABI libraries exist inside the AARs.

When invoked via `build-all.sh`, it requires every component to be freshly built in `out/`. When invoked standalone or via `dev-run.sh`, it supports partial installations using `ONLY_*` flags (or automatically keeps the existing `jniLibs` files for components not present in `out/`, unless `STRICT_PARTIAL=1` is set) and prints a summary banner of any skipped components before and after the Gradle build.

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

This is the development runner, meant for when you don't want to rebuild everything. It supports selecting a single ABI (or `all` for every configured ABI), a stage range, and component-specific `ONLY_*` flags so you can rebuild and package one component without running the stages in between. It also produces detailed logs and tracing, and can run stage 95 for you.

They serve different purposes, so here is how the two runners compare:

| Feature             | build-all.sh                  | dev-run.sh                      |
| :------------------ | :---------------------------- | :------------------------------ |
| Full build          | Yes                           | Yes                             |
| Individual ABI      | No, uses configured ABIS      | Yes (`arm64-v8a`, etc. or `all`)|
| Select stage range  | No                            | Yes                             |
| Single component    | No (requires all payloads)    | Yes (`ONLY_*=1` flags)          |
| Detailed tracing    | No                            | Yes                             |
| Main log file       | No                            | Yes                             |
| Device verification | Manual                        | Can run stage 95                |

For example, this runs only **ffmpeg** for ARM64:

```bash
./dev-run.sh arm64-v8a 60 60
```

And this runs stages 50 through 70 (**Python**, **ffmpeg** and **QuickJS**) for ARM64:

```bash
./dev-run.sh arm64-v8a 50 70
```

If you want to rebuild **ffmpeg** and immediately install and package it into the AARs (stage 90) across all ABIs without running stages 70 or 80 in between, use `ONLY_FFMPEG=1`:

```bash
ONLY_FFMPEG=1 ./dev-run.sh all 60 90
```

Available component flags for `dev-run.sh` and `90-install-payloads.sh`:

| Flag                      | Stage(s) Run         | Notes                                                                 |
| :------------------------ | :------------------- | :-------------------------------------------------------------------- |
| `ONLY_FFMPEG=1`           | `60` (+ `00`, `90`)  | Rebuilds and installs only **ffmpeg** / **ffprobe**                   |
| `ONLY_QUICKJS=1`          | `70` (+ `00`, `90`)  | Rebuilds and installs only **QuickJS-ng**                             |
| `ONLY_ARIA2=1`            | `80` (+ `00`, `90`)  | Rebuilds and installs only **Aria2-Next**                             |
| `ONLY_PYTHON=1`           | `50` (+ `00`, `90`)  | Rebuilds and installs only the **Python** runtime                     |
| `ONLY_LIBFFI=1`           | `10`, `20`, `50` (+ `90`) | Automatically implies `ONLY_CFFI=1` and `ONLY_PYTHON=1` so the rebuilt library and wheel enter `libpython.tar.xz.so` |
| `ONLY_CFFI=1`             | `20`, `50` (+ `90`)       | Automatically implies `ONLY_PYTHON=1` so the wheel enters `libpython.tar.xz.so`  |
| `ONLY_CURL_IMPERSONATE=1` | `30`, `40`, `50` (+ `90`) | Automatically implies `ONLY_CURL_CFFI=1` and `ONLY_PYTHON=1` so the static libs are relinked and enter `libpython.tar.xz.so` |
| `ONLY_CURL_CFFI=1`        | `40`, `50` (+ `90`)       | Automatically implies `ONLY_PYTHON=1` so the wheel enters `libpython.tar.xz.so`  |
| `STRICT_PARTIAL=1`        | `90`                 | Fails if any component is missing from `out/` when no `ONLY_*` flag is set |


#### apply-termux-patches.sh

This script applies the custom patches to the **Termux** packages repository. The patches themselves are listed in the `patches/termux/` section below.

## Folders
Besides the scripts, the folder has two subfolders.

#### aria2-next/

This folder contains the custom **Termux** build recipe for **Aria2-Next**, which is what stage 80 installs, since the package doesn't exist in **termux-packages**.

`build.sh` defines how **Termux** downloads, checks out, builds and installs **Aria2-Next** (with `-Oz`, ThinLTO, and shared prebuilt FFmpeg/system dependencies), while `0001-android-multi-arch.patch` adjusts target selection for arm32, arm64, and x86_64 **Android** builds, wires up prebuilt FFmpeg and Termux shared OpenSSL/SQLite/Expat/zlib, enables Android ThinLTO, and disables `libtorrent` debug logging.


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

| Output                | Purpose                                                   |
| :-------------------- | :-------------------------------------------------------- |
| `libpython.so`        | **Python** interpreter launcher                           |
| `libpython.tar.xz.so` | **Python** standard library and modules (BCJ `tar.xz`)    |
| `libqjs-cli.so`       | Standalone **QuickJS** CLI executable (statically linked) |
| `libffmpeg.so`        | **ffmpeg** executable                                     |
| `libffprobe.so`       | **ffprobe** executable                                    |
| `libffmpeg.tar.xz.so` | **ffmpeg** dependency libraries and C++ runtime (`tar.xz`)|
| `libaria2c.so`        | **aria2-next** executable                                 |

These are packaged into the release AAR under `jni/<ABI>/`.

- - -

# Final Word

One last thing, although I have tested these to death, you might face a problem, as everything in life, report it please! Tho for the sake of transparency, I am a Kotlin developer and a TypeScript dabbler, anything but a shell script master, these scripts were created using AI tools, although I did my best to check if they have any issues, and they probably have an issue, you can always report it as a ticket and I will do my best to solve it.

I heard that in Belgium in the 2003, a woman had an unexpectedly successful election campaign, a 4000-ish vote suddenly gained, even tho she wasn't the most well known, as much as she wanted to believe, it wasn't because she was a great candidate, but because a flipped a value somewhere in the software that was that was counting the votes, was affected and gave her an unreasonable number, turns out that it was a **COSMIC RAY** (look these up, crazy stuff) somehow effected that software to do the flipping, and sadly, she didn't win, it was corrected ( rigged in my book, the universe chose her!), how is that relevant to this? **STUFF BREAKS ALL THE TIME**, even stuff that should't or technically can't (and i thought it was funny).
