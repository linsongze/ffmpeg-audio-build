#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_DIR="${ROOT_DIR}/ffmpeg"
OUTPUT_DIR="${ROOT_DIR}/out"
DIST_DIR="${ROOT_DIR}/dist"
LOCAL_PREFIX="${ROOT_DIR}/local"
BUILD_DIR="${ROOT_DIR}/build"
DOWNLOAD_DIR="${ROOT_DIR}/downloads"
BUILD_LABEL="${BUILD_LABEL:-mac_arm64}"
FFMPEG_REF="${FFMPEG_REF:-n8.1}"
SAFE_REF="${FFMPEG_REF//\//-}"
ARTIFACT_DIR="${DIST_DIR}/ffmpeg-audio-${BUILD_LABEL}-${SAFE_REF}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
BASE_CFLAGS="-O2 -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
BASE_CPPFLAGS="-I${LOCAL_PREFIX}/include"
BASE_LDFLAGS="-L${LOCAL_PREFIX}/lib -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"

source "${ROOT_DIR}/scripts/build-macos-audio-deps.sh"

join_csv() {
  tr '\n' ' ' | xargs | tr ' ' ','
}

build_pkg_config_path() {
  printf '%s\n' "${LOCAL_PREFIX}/lib/pkgconfig"
}

build_extra_cflags() {
  printf '%s' "${BASE_CPPFLAGS} ${BASE_CFLAGS}"
}

build_extra_ldflags() {
  printf '%s' "${BASE_LDFLAGS}"
}

write_metadata() {
  {
    echo "ffmpeg_ref=${FFMPEG_REF}"
    echo "build_label=${BUILD_LABEL}"
    echo "runner_arch=$(uname -m)"
    echo "runner_os=$(uname -s)"
    echo "macos_deployment_target=${MACOSX_DEPLOYMENT_TARGET}"
    echo "build_time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${ARTIFACT_DIR}/BUILD_INFO.txt"

  printf '%s\n' "${CONFIGURE_ARGS[@]}" > "${ARTIFACT_DIR}/CONFIGURE_ARGS.txt"
}

assert_no_non_system_dylibs() {
  local binary_name dylib_lines
  binary_name="$1"
  dylib_lines="$(
    otool -L "${OUTPUT_DIR}/bin/${binary_name}" \
      | tail -n +2 \
      | awk '{print $1}' \
      | grep -Ev '^(/usr/lib/|/System/Library/)' || true
  )"
  if [ -n "${dylib_lines}" ]; then
    echo "${binary_name} still depends on non-system dylibs:" >&2
    echo "${dylib_lines}" >&2
    exit 1
  fi
}

write_silence_wav() {
  local wav_path sample_rate channels bits_per_sample data_size byte_rate
  local block_align riff_size
  wav_path="$1"
  sample_rate=44100
  channels=1
  bits_per_sample=16
  data_size=$((sample_rate * channels * bits_per_sample / 8))
  byte_rate=$((sample_rate * channels * bits_per_sample / 8))
  block_align=$((channels * bits_per_sample / 8))
  riff_size=$((data_size + 36))

  perl -e '
    my ($path, $riff_size, $sample_rate, $byte_rate, $block_align, $bits_per_sample, $data_size) = @ARGV;
    open my $fh, ">", $path or die "open $path failed: $!";
    binmode $fh;
    print $fh pack(
      "a4Va4a4VvvVVvva4V",
      "RIFF",
      $riff_size,
      "WAVE",
      "fmt ",
      16,
      1,
      1,
      $sample_rate,
      $byte_rate,
      $block_align,
      $bits_per_sample,
      "data",
      $data_size
    );
    print $fh "\0" x $data_size;
  ' "${wav_path}" "${riff_size}" "${sample_rate}" "${byte_rate}" "${block_align}" "${bits_per_sample}" "${data_size}"
}

smoke_test() {
  local wav_input mp3_output
  wav_input="${DIST_DIR}/silence.wav"
  mp3_output="${DIST_DIR}/silence.mp3"

  write_silence_wav "${wav_input}"
  "${OUTPUT_DIR}/bin/ffmpeg" -hide_banner -y \
    -i "${wav_input}" \
    -c:a libmp3lame -q:a 4 "${mp3_output}"
  "${OUTPUT_DIR}/bin/ffprobe" -hide_banner -v quiet \
    -print_format json -show_streams -show_format "${mp3_output}" \
    > "${DIST_DIR}/silence.ffprobe.json"
}

mkdir -p "${DIST_DIR}"
rm -rf "${OUTPUT_DIR}" "${ARTIFACT_DIR}"
mkdir -p "${OUTPUT_DIR}" "${ARTIFACT_DIR}"

prepare_static_audio_deps

export PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR
PKG_CONFIG_PATH="$(build_pkg_config_path | paste -sd: -)"
PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"
EXTRA_CFLAGS="$(build_extra_cflags)"
EXTRA_LDFLAGS="$(build_extra_ldflags)"

AUDIO_DEMUXERS="$(
  cat <<'EOF' | join_csv
aac ac3 aiff alaw amr ape au caf flac g722 g723_1 g726 g726le gsm ilbc
ircam latm loas mlp mp2 mp3 mov mulaw oga ogg oma opus s16be s16le s24be
s24le s32be s32le s8 sox spdif tak truehd
tta voc w64 wav wv
EOF
)"

AUDIO_MUXERS="$(
  cat <<'EOF' | join_csv
ac3 adts aiff alaw amr au caf codec2 codec2raw eac3 flac g722 g723_1
g726 g726le gsm ilbc ipod ircam latm mlp mp2 mp3 mulaw oga ogg opus rm
s16be s16le s24be s24le s32be s32le s8 sox spdif truehd
tta voc w64 wav wv
EOF
)"

AUDIO_DECODERS="$(
  cat <<'EOF' | join_csv
8svx_exp 8svx_fib aac aac_fixed aac_at aac_latm ac3 ac3_fixed ac3_at
acelp.kelvin adpcm_4xm adpcm_adx adpcm_afc adpcm_agm adpcm_aica
adpcm_argo adpcm_circus adpcm_ct adpcm_dtk adpcm_ea adpcm_ea_maxis_xa
adpcm_ea_r1 adpcm_ea_r2 adpcm_ea_r3 adpcm_ea_xas g722 g726 g726le
adpcm_ima_acorn adpcm_ima_alp adpcm_ima_amv adpcm_ima_apc adpcm_ima_apm
adpcm_ima_cunning adpcm_ima_dat4 adpcm_ima_dk3 adpcm_ima_dk4
adpcm_ima_ea_eacs adpcm_ima_ea_sead adpcm_ima_escape adpcm_ima_hvqm2
adpcm_ima_hvqm4 adpcm_ima_iss adpcm_ima_magix adpcm_ima_moflex
adpcm_ima_mtf adpcm_ima_oki adpcm_ima_pda adpcm_ima_qt adpcm_ima_qt_at
adpcm_ima_rad adpcm_ima_smjpeg adpcm_ima_ssi adpcm_ima_wav adpcm_ima_ws
adpcm_ima_xbox adpcm_ms adpcm_mtaf adpcm_n64 adpcm_psx adpcm_psxc
adpcm_sanyo adpcm_sbpro_2 adpcm_sbpro_3 adpcm_sbpro_4 adpcm_swf
adpcm_thp adpcm_thp_le adpcm_vima adpcm_xa adpcm_xmd adpcm_yamaha
adpcm_zork ahx alac alac_at amrnb amr_nb_at amrwb anull apac ape aptx
aptx_hd atrac1 atrac3 atrac3al atrac3plus atrac3plusal atrac9 on2avc
binkaudio_dct binkaudio_rdft bmv_audio bonk cbd2_dpcm comfortnoise cook
derf_dpcm dfpwm dolby_e dsd_lsbf dsd_lsbf_planar dsd_msbf dsd_msbf_planar
dsicinaudio dss_sp dst dca dvaudio eac3 eac3_at evrc fastaudio flac ftr
g723_1 g728 g729 gremlin_dpcm gsm gsm_ms gsm_ms_at hca hcom iac ilbc
ilbc_at imc interplay_dpcm interplayacm mace3 mace6 metasound misc4 mlp
mp1 mp1float mp1_at mp2 mp2float mp2_at mp3float mp3 mp3_at mp3adufloat
mp3adu mp3on4float mp3on4 als msnsiren mpc7 mpc8 nellymoser opus libopus
osq paf_audio pcm_alaw pcm_alaw_at pcm_bluray pcm_dvd pcm_f16le pcm_f24le
pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_lxf pcm_mulaw pcm_mulaw_at
pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar pcm_s24be
pcm_s24daud pcm_s24le pcm_s24le_planar pcm_s32be pcm_s32le
pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar pcm_sga
pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8
pcm_vidc qcelp qdm2 qdm2_at qdmc qdmc_at qoa real_144 real_288 ralf rka
roq_dpcm s302m sbc sdx2_dpcm shorten sipr siren smackaud sol_dpcm sonic
speex tak truehd truespeech tta twinvq vmdaudio vorbis libvorbis wady_dpcm
wavarc wavesynth wavpack ws_snd1 wmalossless wmapro wmav1 wmav2 wmavoice
xan_dpcm xma1 xma2
EOF
)"

AUDIO_ENCODERS="$(
  cat <<'EOF' | join_csv
aac aac_at ac3 ac3_fixed adpcm_adx adpcm_argo g722 g726 g726le
adpcm_ima_alp adpcm_ima_amv adpcm_ima_apm adpcm_ima_qt adpcm_ima_ssi
adpcm_ima_wav adpcm_ima_ws adpcm_ms adpcm_swf adpcm_yamaha alac alac_at
anull aptx aptx_hd comfortnoise dfpwm dca eac3 flac g723_1 ilbc_at mlp
mp2 mp2fixed libmp3lame nellymoser opus libopus pcm_alaw pcm_alaw_at
pcm_bluray pcm_dvd pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_mulaw
pcm_mulaw_at pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar
pcm_s24be pcm_s24daud pcm_s24le pcm_s24le_planar pcm_s32be pcm_s32le
pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar pcm_u16be
pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8 pcm_vidc
real_144 roq_dpcm s302m sbc truehd tta vorbis libvorbis wavpack wmav1
wmav2
EOF
)"

AUDIO_FILTERS="$(
  cat <<'EOF' | join_csv
aap abench acompressor acontrast acopy acue acrossfade acrossover
acrusher adeclick adeclip adecorrelate adelay adenorm aderivative adrc
adynamicequalizer adynamicsmooth aecho aemphasis aeval aexciter afade
afftdn afftfilt afir aformat afreqshift afwtdn agate aiir aintegral
ainterleave alatency alimiter allpass aloop amerge ametadata amix
amultiply anequalizer anlmdn anlmf anlms anull apad aperms aphaser
aphaseshift apsnr apsyclip apulsator arealtime aresample areverse arls
arnndn asdr asegment aselect asendcmd asetnsamples asetpts asetrate
asettb ashowinfo asidedata asisdr asoftclip aspectralstats asplit astats
asubboost asubcut asupercut asuperpass asuperstop atempo atilt atrim
axcorrelate bandpass bandreject bass biquad channelmap channelsplit chorus
compand compensationdelay crossfeed crystalizer dcshift deesser
dialoguenhance drmeter dynaudnorm earwax ebur128 equalizer extrastereo
firequalizer flanger haas hdcd headphone highpass highshelf join loudnorm
lowpass lowshelf mcompand pan replaygain sidechaincompress sidechaingate
silencedetect silenceremove speechnorm stereotools stereowiden
superequalizer surround tiltshelf treble tremolo vibrato virtualbass
volume volumedetect aevalsrc afdelaysrc afireqsrc afirsrc anoisesrc
anullsrc hilbert sinc sine anullsink aphasemeter abuffer abuffersink
EOF
)"

AUDIO_PARSERS="aac,aac_latm,ac3,adx,aptx,dca,flac,g723_1,g729,gsm,mlp,mpegaudio,opus,sipr,tak,vorbis"
AUDIO_BSFS="aac_adtstoasc,chomp,dca_core,dump_extra,eac3_core,extract_extradata,mp3decomp,opus_metadata,pcm_rechunk,setts,truehd_core,null"

CONFIGURE_ARGS=(
  --prefix="${OUTPUT_DIR}"
  --arch=arm64
  --target-os=darwin
  --cc=clang
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
  --disable-videotoolbox
  --disable-shared
  --enable-static
  --disable-everything
  --enable-ffmpeg
  --enable-ffprobe
  --enable-avcodec
  --enable-avformat
  --enable-avfilter
  --enable-swresample
  --disable-audiotoolbox
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

cd "${FFMPEG_DIR}"
export MACOSX_DEPLOYMENT_TARGET
./configure "${CONFIGURE_ARGS[@]}"
make -j"$(sysctl -n hw.ncpu)"
make install

strip -x "${OUTPUT_DIR}/bin/ffmpeg" "${OUTPUT_DIR}/bin/ffprobe"
assert_no_non_system_dylibs "ffmpeg"
assert_no_non_system_dylibs "ffprobe"
cp "${OUTPUT_DIR}/bin/ffmpeg" "${ARTIFACT_DIR}/ffmpeg"
cp "${OUTPUT_DIR}/bin/ffprobe" "${ARTIFACT_DIR}/ffprobe"

write_metadata
smoke_test
