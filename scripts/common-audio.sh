#!/bin/bash

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
    return
  fi

  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return
  fi

  printf '4\n'
}

join_csv() {
  tr '\n' ' ' | xargs | tr ' ' ','
}

setup_audio_feature_lists() {
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
8svx_exp 8svx_fib aac aac_fixed aac_latm ac3 ac3_fixed
acelp.kelvin adpcm_4xm adpcm_adx adpcm_afc adpcm_agm adpcm_aica
adpcm_argo adpcm_circus adpcm_ct adpcm_dtk adpcm_ea adpcm_ea_maxis_xa
adpcm_ea_r1 adpcm_ea_r2 adpcm_ea_r3 adpcm_ea_xas g722 g726 g726le
adpcm_ima_acorn adpcm_ima_alp adpcm_ima_amv adpcm_ima_apc adpcm_ima_apm
adpcm_ima_cunning adpcm_ima_dat4 adpcm_ima_dk3 adpcm_ima_dk4
adpcm_ima_ea_eacs adpcm_ima_ea_sead adpcm_ima_escape adpcm_ima_hvqm2
adpcm_ima_hvqm4 adpcm_ima_iss adpcm_ima_magix adpcm_ima_moflex
adpcm_ima_mtf adpcm_ima_oki adpcm_ima_pda adpcm_ima_qt
adpcm_ima_rad adpcm_ima_smjpeg adpcm_ima_ssi adpcm_ima_wav adpcm_ima_ws
adpcm_ima_xbox adpcm_ms adpcm_mtaf adpcm_n64 adpcm_psx adpcm_psxc
adpcm_sanyo adpcm_sbpro_2 adpcm_sbpro_3 adpcm_sbpro_4 adpcm_swf
adpcm_thp adpcm_thp_le adpcm_vima adpcm_xa adpcm_xmd adpcm_yamaha
adpcm_zork ahx alac amrnb amrwb anull apac ape aptx
aptx_hd atrac1 atrac3 atrac3al atrac3plus atrac3plusal atrac9 on2avc
binkaudio_dct binkaudio_rdft bmv_audio bonk cbd2_dpcm comfortnoise cook
derf_dpcm dfpwm dolby_e dsd_lsbf dsd_lsbf_planar dsd_msbf dsd_msbf_planar
dsicinaudio dss_sp dst dca dvaudio eac3 evrc fastaudio flac ftr
g723_1 g728 g729 gremlin_dpcm gsm gsm_ms hca hcom iac ilbc
imc interplay_dpcm interplayacm mace3 mace6 metasound misc4 mlp
mp1 mp1float mp2 mp2float mp3float mp3 mp3adufloat
mp3adu mp3on4float mp3on4 als msnsiren mpc7 mpc8 nellymoser opus libopus
osq paf_audio pcm_alaw pcm_bluray pcm_dvd pcm_f16le pcm_f24le
pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_lxf pcm_mulaw
pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar pcm_s24be
pcm_s24daud pcm_s24le pcm_s24le_planar pcm_s32be pcm_s32le
pcm_s32le_planar pcm_s64be pcm_s64le pcm_s8 pcm_s8_planar pcm_sga
pcm_u16be pcm_u16le pcm_u24be pcm_u24le pcm_u32be pcm_u32le pcm_u8
pcm_vidc qcelp qdm2 qdmc qoa real_144 real_288 ralf rka
roq_dpcm s302m sbc sdx2_dpcm shorten sipr siren smackaud sol_dpcm sonic
speex tak truehd truespeech tta twinvq vmdaudio vorbis libvorbis wady_dpcm
wavarc wavesynth wavpack ws_snd1 wmalossless wmapro wmav1 wmav2 wmavoice
xan_dpcm xma1 xma2
EOF
  )"

  AUDIO_ENCODERS="$(
    cat <<'EOF' | join_csv
aac ac3 ac3_fixed adpcm_adx adpcm_argo g722 g726 g726le
adpcm_ima_alp adpcm_ima_amv adpcm_ima_apm adpcm_ima_qt adpcm_ima_ssi
adpcm_ima_wav adpcm_ima_ws adpcm_ms adpcm_swf adpcm_yamaha alac
anull aptx aptx_hd comfortnoise dfpwm dca eac3 flac g723_1 mlp
mp2 mp2fixed libmp3lame nellymoser opus libopus pcm_alaw
pcm_bluray pcm_dvd pcm_f32be pcm_f32le pcm_f64be pcm_f64le pcm_mulaw
pcm_s16be pcm_s16be_planar pcm_s16le pcm_s16le_planar
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
}

binary_name() {
  local base_name
  base_name="$1"

  if [ "${TARGET_OS_FAMILY}" = "windows" ]; then
    printf '%s.exe\n' "${base_name}"
    return
  fi

  printf '%s\n' "${base_name}"
}

write_silence_wav() {
  local wav_path duration_seconds sample_rate channels bits_per_sample data_size
  local byte_rate block_align riff_size

  wav_path="$1"
  duration_seconds="${2:-2}"
  sample_rate=44100
  channels=1
  bits_per_sample=16
  data_size=$((sample_rate * channels * bits_per_sample / 8 * duration_seconds))
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
      $block_align / ($bits_per_sample / 8),
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

assert_duration_between() {
  local ffprobe_bin media_path min_duration max_duration duration
  ffprobe_bin="$1"
  media_path="$2"
  min_duration="$3"
  max_duration="$4"
  duration="$("${ffprobe_bin}" -hide_banner -v error -show_entries format=duration -of default=nw=1:nk=1 "${media_path}" | tr -d '\r')"

  awk -v duration="${duration}" -v min_duration="${min_duration}" -v max_duration="${max_duration}" '
    BEGIN {
      if (duration < min_duration || duration > max_duration) {
        exit 1
      }
    }
  '
}

assert_codec_name() {
  local ffprobe_bin media_path expected_codec actual_codec
  ffprobe_bin="$1"
  media_path="$2"
  expected_codec="$3"
  actual_codec="$("${ffprobe_bin}" -hide_banner -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "${media_path}" | tr -d '\r')"

  if [ "${actual_codec}" != "${expected_codec}" ]; then
    echo "unexpected codec for ${media_path}: expected ${expected_codec}, got ${actual_codec}" >&2
    exit 1
  fi
}

run_smoke_tests() {
  local ffmpeg_bin ffprobe_bin work_dir wav_input mp3_output m4a_output
  local clip_output roundtrip_output

  ffmpeg_bin="$1"
  ffprobe_bin="$2"
  work_dir="$3"
  wav_input="${work_dir}/silence.wav"
  mp3_output="${work_dir}/silence.mp3"
  m4a_output="${work_dir}/silence.m4a"
  clip_output="${work_dir}/clip.wav"
  roundtrip_output="${work_dir}/from-m4a.mp3"

  mkdir -p "${work_dir}"
  write_silence_wav "${wav_input}" 2

  "${ffmpeg_bin}" -hide_banner -version > /dev/null
  "${ffprobe_bin}" -hide_banner -version > /dev/null

  "${ffmpeg_bin}" -hide_banner -y \
    -i "${wav_input}" \
    -c:a libmp3lame -q:a 4 "${mp3_output}"

  "${ffmpeg_bin}" -hide_banner -y \
    -i "${wav_input}" \
    -c:a aac -b:a 128k "${m4a_output}"

  "${ffmpeg_bin}" -hide_banner -y \
    -ss 0.50 -t 0.75 \
    -i "${wav_input}" \
    -c:a pcm_s16le "${clip_output}"

  "${ffmpeg_bin}" -hide_banner -y \
    -i "${m4a_output}" \
    -c:a libmp3lame -q:a 4 "${roundtrip_output}"

  assert_codec_name "${ffprobe_bin}" "${mp3_output}" "mp3"
  assert_codec_name "${ffprobe_bin}" "${m4a_output}" "aac"
  assert_codec_name "${ffprobe_bin}" "${clip_output}" "pcm_s16le"
  assert_codec_name "${ffprobe_bin}" "${roundtrip_output}" "mp3"

  assert_duration_between "${ffprobe_bin}" "${mp3_output}" 1.90 2.10
  assert_duration_between "${ffprobe_bin}" "${m4a_output}" 1.90 2.10
  assert_duration_between "${ffprobe_bin}" "${clip_output}" 0.70 0.80
  assert_duration_between "${ffprobe_bin}" "${roundtrip_output}" 1.90 2.15
}
