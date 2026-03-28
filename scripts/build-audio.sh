#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/common-audio.sh"

TARGET_TRIPLE="${TARGET_TRIPLE:?TARGET_TRIPLE is required}"
TARGET_OS_FAMILY="${TARGET_OS_FAMILY:?TARGET_OS_FAMILY is required}"
TARGET_FFMPEG_ARCH="${TARGET_FFMPEG_ARCH:?TARGET_FFMPEG_ARCH is required}"
TARGET_FFMPEG_OS="${TARGET_FFMPEG_OS:?TARGET_FFMPEG_OS is required}"

FFMPEG_DIR="${ROOT_DIR}/ffmpeg"
OUTPUT_DIR="${ROOT_DIR}/out"
DIST_DIR="${ROOT_DIR}/dist"
DOWNLOAD_DIR="${ROOT_DIR}/downloads"
BUILD_DIR="${ROOT_DIR}/build"
BUILD_LABEL="${BUILD_LABEL:-${TARGET_TRIPLE}}"
FFMPEG_REF="${FFMPEG_REF:-n8.1}"
SAFE_REF="${FFMPEG_REF//\//-}"
ARTIFACT_DIR="${DIST_DIR}/ffmpeg-audio-${BUILD_LABEL}-${SAFE_REF}"

LOCAL_PREFIX="${ROOT_DIR}/local"
OUTPUT_PREFIX="${OUTPUT_DIR}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

normalize_windows_command() {
  local command_value
  command_value="$1"

  case "${command_value}" in
    [A-Za-z]:\\*|[A-Za-z]:/*)
      cygpath -u "${command_value}"
      ;;
    *)
      printf '%s\n' "${command_value}"
      ;;
  esac
}

write_windows_pkgconf_wrapper() {
  local resolved_command wrapper_path escaped_command
  resolved_command="$1"
  wrapper_path="${BUILD_DIR}/windows-pkgconf.sh"
  escaped_command="${resolved_command//\'/\'\\\'\'}"

  mkdir -p "${BUILD_DIR}"
  cat > "${wrapper_path}" <<EOF
#!/bin/sh
exec '${escaped_command}' "\$@"
EOF
  chmod +x "${wrapper_path}"
  printf '%s\n' "${wrapper_path}"
}

resolve_windows_pkgconf() {
  local preferred_command candidate normalized_candidate
  preferred_command="$1"

  for candidate in "${preferred_command}" pkg-config.exe pkgconf.exe pkg-config pkgconf; do
    [ -n "${candidate}" ] || continue
    normalized_candidate="$(normalize_windows_command "${candidate}")"

    if [[ "${normalized_candidate}" == */* ]]; then
      [ -e "${normalized_candidate}" ] || continue
      if "${normalized_candidate}" --version >/dev/null 2>&1; then
        write_windows_pkgconf_wrapper "${normalized_candidate}"
        return
      fi
      continue
    fi

    if command -v "${normalized_candidate}" >/dev/null 2>&1 && "${normalized_candidate}" --version >/dev/null 2>&1; then
      write_windows_pkgconf_wrapper "${normalized_candidate}"
      return
    fi
  done

  echo "unable to locate a working pkg-config command for Windows builds" >&2
  return 1
}

case "${TARGET_OS_FAMILY}" in
  darwin)
    BASE_CFLAGS="-O2 -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
    BASE_CPPFLAGS="-I${LOCAL_PREFIX}/include"
    BASE_LDFLAGS="-L${LOCAL_PREFIX}/lib -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
    source "${ROOT_DIR}/scripts/build-posix-audio-deps.sh"
    ;;
  linux)
    BASE_CFLAGS="-O2"
    BASE_CPPFLAGS="-I${LOCAL_PREFIX}/include"
    BASE_LDFLAGS="-L${LOCAL_PREFIX}/lib"
    source "${ROOT_DIR}/scripts/build-posix-audio-deps.sh"
    ;;
  windows)
    LOCAL_PREFIX="$(cygpath -u "${WINDOWS_VCPKG_INSTALLED_DIR:?WINDOWS_VCPKG_INSTALLED_DIR is required for Windows builds}")"
    PKGCONF_EXE="$(resolve_windows_pkgconf "${PKGCONF_EXE:?PKGCONF_EXE is required for Windows builds}")"
    LOCAL_PREFIX_NATIVE="$(cygpath -m "${LOCAL_PREFIX}")"
    OUTPUT_PREFIX="$(cygpath -m "${OUTPUT_DIR}")"
    BASE_CFLAGS="-O2 -MT"
    BASE_CPPFLAGS="-I${LOCAL_PREFIX_NATIVE}/include"
    BASE_LDFLAGS="-libpath:${LOCAL_PREFIX_NATIVE}/lib"
    ;;
  *)
    echo "unsupported TARGET_OS_FAMILY: ${TARGET_OS_FAMILY}" >&2
    exit 1
    ;;
esac

build_pkg_config_path() {
  if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
    printf '%s\n' "${LOCAL_PREFIX_NATIVE}/lib/pkgconfig"
    printf '%s\n' "${LOCAL_PREFIX_NATIVE}/share/pkgconfig"
    return
  fi

  printf '%s\n' "${LOCAL_PREFIX}/lib/pkgconfig"
}

pkg_config_separator() {
  if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
    printf ';\n'
    return
  fi

  printf ':\n'
}

build_extra_cflags() {
  printf '%s %s' "${BASE_CPPFLAGS}" "${BASE_CFLAGS}"
}

build_extra_ldflags() {
  printf '%s' "${BASE_LDFLAGS}"
}

write_metadata() {
  {
    echo "ffmpeg_ref=${FFMPEG_REF}"
    echo "build_label=${BUILD_LABEL}"
    echo "target_triple=${TARGET_TRIPLE}"
    echo "runner_arch=$(uname -m)"
    echo "runner_os=$(uname -s)"
    if [ "${TARGET_OS_FAMILY}" = "darwin" ]; then
      echo "macos_deployment_target=${MACOSX_DEPLOYMENT_TARGET}"
    fi
    echo "build_time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${ARTIFACT_DIR}/BUILD_INFO.txt"

  printf '%s\n' "${CONFIGURE_ARGS[@]}" > "${ARTIFACT_DIR}/CONFIGURE_ARGS.txt"
}

strip_binary() {
  local binary_path
  binary_path="$1"

  case "${TARGET_OS_FAMILY}" in
    darwin)
      strip -x "${binary_path}"
      ;;
    linux)
      strip --strip-unneeded "${binary_path}" || true
      ;;
    windows)
      if command -v llvm-strip >/dev/null 2>&1; then
        llvm-strip "${binary_path}" || true
      fi
      ;;
  esac
}

apply_windows_ffmpeg_patches() {
  patch --batch --binary -N -p1 < "${ROOT_DIR}/scripts/patches/ffmpeg-windows-msvc-depcmd.patch"
}

mkdir -p "${DIST_DIR}"
rm -rf "${OUTPUT_DIR}" "${ARTIFACT_DIR}"
mkdir -p "${OUTPUT_DIR}" "${ARTIFACT_DIR}"

if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
  if [ ! -d "${LOCAL_PREFIX}" ]; then
    echo "missing Windows static dependency prefix: ${LOCAL_PREFIX}" >&2
    exit 1
  fi
else
  prepare_static_audio_deps
fi

setup_audio_feature_lists

export PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR
PKG_CONFIG_PATH="$(build_pkg_config_path | paste -sd"$(pkg_config_separator)" -)"
PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"

if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
  echo "using Windows pkg-config wrapper: ${PKGCONF_EXE}"
fi

EXTRA_CFLAGS="$(build_extra_cflags)"
EXTRA_LDFLAGS="$(build_extra_ldflags)"

CONFIGURE_ARGS=(
  --prefix="${OUTPUT_PREFIX}"
  --arch="${TARGET_FFMPEG_ARCH}"
  --target-os="${TARGET_FFMPEG_OS}"
  --pkg-config-flags=--static
  --extra-cflags="${EXTRA_CFLAGS}"
  --extra-ldflags="${EXTRA_LDFLAGS}"
  --disable-doc
  --disable-debug
  --enable-small
  --disable-network
  --disable-autodetect
  --disable-ffplay
  --disable-avdevice
  --disable-swscale
  --disable-hwaccels
  --disable-shared
  --enable-static
  --disable-everything
  --enable-ffmpeg
  --enable-ffprobe
  --enable-avcodec
  --enable-avformat
  --enable-avfilter
  --enable-swresample
  --enable-protocol=file
  --enable-protocol=pipe
  --enable-demuxer="${AUDIO_DEMUXERS}"
  --enable-muxer="${AUDIO_MUXERS}"
  --enable-decoder="${AUDIO_DECODERS}"
  --enable-encoder="${AUDIO_ENCODERS}"
  --enable-filter="${AUDIO_FILTERS}"
  --enable-parser="${AUDIO_PARSERS}"
  --enable-bsf="${AUDIO_BSFS}"
  --enable-libmp3lame
  --enable-libopus
  --enable-libvorbis
)

if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
  CONFIGURE_ARGS+=(
    --pkg-config="${PKGCONF_EXE}"
    --toolchain=msvc
  )
fi

if [ "${TARGET_OS_FAMILY}" = "darwin" ]; then
  CONFIGURE_ARGS+=(
    --disable-audiotoolbox
    --disable-videotoolbox
  )
fi

if [ "${TARGET_FFMPEG_ARCH}" = "x86_64" ]; then
  CONFIGURE_ARGS+=(
    --disable-x86asm
  )
fi

if [ "${TARGET_OS_FAMILY}" = "windows" ] && [ "${TARGET_FFMPEG_ARCH}" = "aarch64" ]; then
  CONFIGURE_ARGS+=(
    --disable-asm
  )
fi

cd "${FFMPEG_DIR}"

if [ "${TARGET_OS_FAMILY}" = "darwin" ]; then
  export MACOSX_DEPLOYMENT_TARGET
fi

if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
  apply_windows_ffmpeg_patches
fi

if ! ./configure "${CONFIGURE_ARGS[@]}"; then
  if [ -f ffbuild/config.log ]; then
    echo "===== ffbuild/config.log =====" >&2
    tail -n 240 ffbuild/config.log >&2 || true
  fi
  exit 1
fi

make -j"$(cpu_count)"
make install

FFMPEG_BINARY="${OUTPUT_DIR}/bin/$(binary_name ffmpeg)"
FFPROBE_BINARY="${OUTPUT_DIR}/bin/$(binary_name ffprobe)"

strip_binary "${FFMPEG_BINARY}"
strip_binary "${FFPROBE_BINARY}"

cp "${FFMPEG_BINARY}" "${ARTIFACT_DIR}/$(binary_name ffmpeg)"
cp "${FFPROBE_BINARY}" "${ARTIFACT_DIR}/$(binary_name ffprobe)"

write_metadata
run_smoke_tests "${FFMPEG_BINARY}" "${FFPROBE_BINARY}" "${DIST_DIR}/smoke"
