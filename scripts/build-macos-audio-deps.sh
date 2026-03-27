#!/bin/bash

LAME_VERSION="3.100"
LIBOGG_VERSION="1.3.6"
LIBVORBIS_VERSION="1.3.7"
OPUS_VERSION="1.5.2"

LAME_URL="https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
LIBOGG_URL="https://downloads.xiph.org/releases/ogg/libogg-${LIBOGG_VERSION}.tar.gz"
LIBVORBIS_URL="https://downloads.xiph.org/releases/vorbis/libvorbis-${LIBVORBIS_VERSION}.tar.gz"
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"

require_file() {
  local file_path
  file_path="$1"
  if [ ! -f "${file_path}" ]; then
    echo "missing required file: ${file_path}" >&2
    exit 1
  fi
}

download_and_extract() {
  local name url archive_name archive_path source_dir
  name="$1"
  url="$2"
  archive_name="$3"
  archive_path="${DOWNLOAD_DIR}/${archive_name}"
  source_dir="${BUILD_DIR}/${name}"

  rm -rf "${source_dir}"
  mkdir -p "${DOWNLOAD_DIR}" "${BUILD_DIR}"
  curl -fsSL "${url}" -o "${archive_path}"
  mkdir -p "${source_dir}"
  tar -xzf "${archive_path}" -C "${source_dir}" --strip-components=1
  printf '%s\n' "${source_dir}"
}

run_configure() {
  local source_dir
  source_dir="$1"
  shift
  (
    cd "${source_dir}"
    env \
      MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}" \
      CFLAGS="${BASE_CFLAGS}" \
      CXXFLAGS="${BASE_CFLAGS}" \
      CPPFLAGS="${BASE_CPPFLAGS}" \
      LDFLAGS="${BASE_LDFLAGS}" \
      PKG_CONFIG_PATH="${LOCAL_PREFIX}/lib/pkgconfig" \
      PKG_CONFIG_LIBDIR="${LOCAL_PREFIX}/lib/pkgconfig" \
      ./configure "$@"
  )
}

build_with_configure_install() {
  local source_dir
  source_dir="$1"
  shift
  run_configure "${source_dir}" "$@"
  (
    cd "${source_dir}"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
}

install_static_archive() {
  local source_file target_dir
  source_file="$1"
  target_dir="$2"
  require_file "${source_file}"
  mkdir -p "${target_dir}"
  cp "${source_file}" "${target_dir}/"
  ranlib "${target_dir}/$(basename "${source_file}")"
}

install_include_file() {
  local source_file target_dir
  source_file="$1"
  target_dir="$2"
  require_file "${source_file}"
  mkdir -p "${target_dir}"
  cp "${source_file}" "${target_dir}/"
}

install_pkgconfig_file() {
  local source_file
  source_file="$1"
  install_include_file "${source_file}" "${LOCAL_PREFIX}/lib/pkgconfig"
}

write_lame_pkgconfig_file() {
  mkdir -p "${LOCAL_PREFIX}/lib/pkgconfig"
  cat > "${LOCAL_PREFIX}/lib/pkgconfig/lame.pc" <<EOF
prefix=${LOCAL_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: lame
Description: LAME MP3 encoder library
Version: ${LAME_VERSION}
Libs: -L\${libdir} -lmp3lame
Libs.private: -lm
Cflags: -I\${includedir}
EOF
}

build_libogg() {
  local source_dir
  source_dir="$(download_and_extract "libogg" "${LIBOGG_URL}" "libogg-${LIBOGG_VERSION}.tar.gz")"
  build_with_configure_install \
    "${source_dir}" \
    --prefix="${LOCAL_PREFIX}" \
    --disable-shared \
    --enable-static
}

build_opus() {
  local source_dir
  source_dir="$(download_and_extract "opus" "${OPUS_URL}" "opus-${OPUS_VERSION}.tar.gz")"
  build_with_configure_install \
    "${source_dir}" \
    --prefix="${LOCAL_PREFIX}" \
    --disable-shared \
    --enable-static
}

install_static_libvorbis() {
  local source_dir
  source_dir="$1"
  install_static_archive "${source_dir}/lib/.libs/libvorbis.a" "${LOCAL_PREFIX}/lib"
  install_static_archive "${source_dir}/lib/.libs/libvorbisenc.a" "${LOCAL_PREFIX}/lib"
  install_static_archive "${source_dir}/lib/.libs/libvorbisfile.a" "${LOCAL_PREFIX}/lib"
  install_include_file "${source_dir}/include/vorbis/codec.h" "${LOCAL_PREFIX}/include/vorbis"
  install_include_file "${source_dir}/include/vorbis/vorbisenc.h" "${LOCAL_PREFIX}/include/vorbis"
  install_include_file "${source_dir}/include/vorbis/vorbisfile.h" "${LOCAL_PREFIX}/include/vorbis"
  install_pkgconfig_file "${source_dir}/vorbis.pc"
  install_pkgconfig_file "${source_dir}/vorbisenc.pc"
  install_pkgconfig_file "${source_dir}/vorbisfile.pc"
}

build_libvorbis() {
  local source_dir
  source_dir="$(download_and_extract "libvorbis" "${LIBVORBIS_URL}" "libvorbis-${LIBVORBIS_VERSION}.tar.gz")"
  run_configure \
    "${source_dir}" \
    --prefix="${LOCAL_PREFIX}" \
    --disable-shared \
    --enable-static
  (
    cd "${source_dir}"
    make -C lib libvorbis.la libvorbisenc.la libvorbisfile.la -j"$(sysctl -n hw.ncpu)"
  )
  install_static_libvorbis "${source_dir}"
}

build_lame() {
  local source_dir
  source_dir="$(download_and_extract "lame" "${LAME_URL}" "lame-${LAME_VERSION}.tar.gz")"
  build_with_configure_install \
    "${source_dir}" \
    --prefix="${LOCAL_PREFIX}" \
    --disable-shared \
    --enable-static
  write_lame_pkgconfig_file
}

assert_static_dep_outputs() {
  require_file "${LOCAL_PREFIX}/lib/libogg.a"
  require_file "${LOCAL_PREFIX}/lib/libopus.a"
  require_file "${LOCAL_PREFIX}/lib/libvorbis.a"
  require_file "${LOCAL_PREFIX}/lib/libvorbisenc.a"
  require_file "${LOCAL_PREFIX}/lib/libvorbisfile.a"
  require_file "${LOCAL_PREFIX}/lib/libmp3lame.a"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/ogg.pc"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/opus.pc"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/lame.pc"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/vorbis.pc"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/vorbisenc.pc"
  require_file "${LOCAL_PREFIX}/lib/pkgconfig/vorbisfile.pc"
}

prepare_static_audio_deps() {
  rm -rf "${LOCAL_PREFIX}" "${BUILD_DIR}"
  mkdir -p "${LOCAL_PREFIX}" "${BUILD_DIR}" "${DOWNLOAD_DIR}"
  build_libogg
  build_opus
  build_libvorbis
  build_lame
  assert_static_dep_outputs
}
