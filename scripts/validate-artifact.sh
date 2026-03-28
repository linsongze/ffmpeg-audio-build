#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/common-audio.sh"

TARGET_TRIPLE="${TARGET_TRIPLE:?TARGET_TRIPLE is required}"
TARGET_OS_FAMILY="${TARGET_OS_FAMILY:?TARGET_OS_FAMILY is required}"
VALIDATE_ARTIFACT_DIR="${1:?artifact directory is required}"

FFMPEG_BINARY="${VALIDATE_ARTIFACT_DIR}/$(binary_name ffmpeg)"
FFPROBE_BINARY="${VALIDATE_ARTIFACT_DIR}/$(binary_name ffprobe)"

if [ "${TARGET_OS_FAMILY}" != "windows" ]; then
  chmod +x "${FFMPEG_BINARY}" "${FFPROBE_BINARY}"
fi

assert_binary_architecture() {
  local binary_path file_output expected_pattern
  binary_path="$1"
  file_output="$(file "${binary_path}" | tr -d '\r')"
  printf '%s\n' "${file_output}"

  case "${TARGET_TRIPLE}" in
    aarch64-apple-darwin)
      expected_pattern='(arm64|aarch64)'
      ;;
    x86_64-apple-darwin)
      expected_pattern='x86_64'
      ;;
    x86_64-unknown-linux-gnu)
      expected_pattern='x86-64'
      ;;
    aarch64-unknown-linux-gnu)
      expected_pattern='(ARM aarch64|aarch64)'
      ;;
    x86_64-pc-windows-msvc)
      expected_pattern='(x86-64|x86_64)'
      ;;
    aarch64-pc-windows-msvc)
      expected_pattern='(Aarch64|ARM64|aarch64)'
      ;;
    *)
      echo "unsupported TARGET_TRIPLE: ${TARGET_TRIPLE}" >&2
      exit 1
      ;;
  esac

  if ! printf '%s\n' "${file_output}" | grep -Eiq "${expected_pattern}"; then
    echo "$(basename "${binary_path}") does not match expected architecture for ${TARGET_TRIPLE}" >&2
    exit 1
  fi
}

validate_darwin_binary() {
  local binary_path binary_name_local dylib_lines build_version_lines
  binary_path="$1"
  binary_name_local="$(basename "${binary_path}")"

  echo "== ${binary_name_local} dylibs =="
  otool -L "${binary_path}"
  dylib_lines="$(
    otool -L "${binary_path}" \
      | tail -n +2 \
      | awk '{print $1}' \
      | grep -Ev '^(/usr/lib/|/System/Library/)' || true
  )"
  if [ -n "${dylib_lines}" ]; then
    echo "${binary_name_local} still depends on non-system dylibs:" >&2
    echo "${dylib_lines}" >&2
    exit 1
  fi

  echo "== ${binary_name_local} build version =="
  build_version_lines="$(otool -l "${binary_path}" | grep -A3 'LC_BUILD_VERSION\|LC_VERSION_MIN_MACOSX')"
  printf '%s\n' "${build_version_lines}"
  if ! printf '%s\n' "${build_version_lines}" | grep -q "minos ${MACOSX_DEPLOYMENT_TARGET:?MACOSX_DEPLOYMENT_TARGET is required}"; then
    echo "${binary_name_local} does not target macOS ${MACOSX_DEPLOYMENT_TARGET}" >&2
    exit 1
  fi
}

validate_linux_binary() {
  local binary_path binary_name_local ldd_output
  binary_path="$1"
  binary_name_local="$(basename "${binary_path}")"

  echo "== ${binary_name_local} ldd =="
  ldd_output="$(ldd "${binary_path}" || true)"
  printf '%s\n' "${ldd_output}"

  if printf '%s\n' "${ldd_output}" | grep -q 'not found'; then
    echo "${binary_name_local} has unresolved shared library dependencies" >&2
    exit 1
  fi

  if printf '%s\n' "${ldd_output}" | grep -Eiq 'lib(mp3lame|vorbis|vorbisenc|vorbisfile|ogg|opus)\.so'; then
    echo "${binary_name_local} still depends on third-party codec shared libraries" >&2
    exit 1
  fi
}

validate_windows_binary() {
  local binary_path binary_name_local dependents_output imported_dlls
  binary_path="$1"
  binary_name_local="$(basename "${binary_path}")"

  echo "== ${binary_name_local} dependents =="
  dependents_output="$(dumpbin.exe /DEPENDENTS "${binary_path}" | tr -d '\r')"
  printf '%s\n' "${dependents_output}"

  imported_dlls="$(
    printf '%s\n' "${dependents_output}" \
      | awk '/^[[:space:]]+[A-Za-z0-9._-]+\.dll$/ { gsub(/^[[:space:]]+/, "", $0); print $0 }'
  )"

  if printf '%s\n' "${imported_dlls}" | grep -Eiq '^(av(codec|format|filter|util)|sw(resample|scale)|postproc|lib(mp3lame|vorbis|vorbisenc|vorbisfile|ogg|opus)|mp3lame|vorbis|ogg|opus).*\.dll$'; then
    echo "${binary_name_local} still depends on third-party codec DLLs" >&2
    exit 1
  fi
}

case "${TARGET_OS_FAMILY}" in
  darwin)
    assert_binary_architecture "${FFMPEG_BINARY}"
    assert_binary_architecture "${FFPROBE_BINARY}"
    validate_darwin_binary "${FFMPEG_BINARY}"
    validate_darwin_binary "${FFPROBE_BINARY}"
    ;;
  linux)
    assert_binary_architecture "${FFMPEG_BINARY}"
    assert_binary_architecture "${FFPROBE_BINARY}"
    validate_linux_binary "${FFMPEG_BINARY}"
    validate_linux_binary "${FFPROBE_BINARY}"
    ;;
  windows)
    assert_binary_architecture "${FFMPEG_BINARY}"
    assert_binary_architecture "${FFPROBE_BINARY}"
    validate_windows_binary "${FFMPEG_BINARY}"
    validate_windows_binary "${FFPROBE_BINARY}"
    ;;
  *)
    echo "unsupported TARGET_OS_FAMILY: ${TARGET_OS_FAMILY}" >&2
    exit 1
    ;;
esac

run_smoke_tests "${FFMPEG_BINARY}" "${FFPROBE_BINARY}" "${VALIDATE_ARTIFACT_DIR}/smoke"
