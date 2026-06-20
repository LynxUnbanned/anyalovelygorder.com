#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/movies/hls"

source_height() {
  ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$1"
}

make_variant() {
  local input="$1"
  local out_dir="$2"
  local label="$3"
  local height="$4"
  local crf="$5"
  local bitrate="$6"
  local maxrate="$7"
  local bufsize="$8"
  local audio_bitrate="${9:-128k}"
  local include_audio="${10:-1}"
  local start_time="${11:-}"
  local duration="${12:-}"

  mkdir -p "$out_dir"

  if [[ "${SKIP_EXISTING:-1}" == "1" && -s "$out_dir/${label}.m3u8" && -s "$out_dir/${label}.ts" ]]; then
    return
  fi

  local video_args
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_videotoolbox"; then
    video_args=(-c:v h264_videotoolbox -b:v "$bitrate" -maxrate "$maxrate" -profile:v main -allow_sw 1 -realtime false -spatial_aq 1)
  else
    video_args=(-c:v libx264 -preset fast -crf "$crf" -maxrate "$maxrate" -bufsize "$bufsize" -profile:v main)
  fi

  local map_args=(-map 0:v:0)
  local audio_args=(-an)
  if [[ "$include_audio" == "1" ]]; then
    map_args+=(-map 0:a:0?)
    audio_args=(-c:a aac -b:a "$audio_bitrate" -ac 2)
  fi

  local ffmpeg_args=(-y)
  if [[ -n "$start_time" ]]; then
    ffmpeg_args+=(-ss "$start_time")
  fi
  if [[ -n "$duration" ]]; then
    ffmpeg_args+=(-t "$duration")
  fi

  ffmpeg "${ffmpeg_args[@]}" -i "$input" \
    "${map_args[@]}" \
    -vf "scale=-2:${height}" \
    "${video_args[@]}" \
    -pix_fmt yuv420p -g 48 -keyint_min 48 -sc_threshold 0 \
    "${audio_args[@]}" \
    -hls_time 6 -hls_playlist_type vod \
    -hls_flags independent_segments+single_file \
    -hls_segment_filename "$out_dir/${label}.ts" \
    "$out_dir/${label}.m3u8"
}

maybe_make_variant() {
  local input="$1"
  local out_dir="$2"
  local label="$3"
  local height="$4"
  local crf="$5"
  local bitrate="$6"
  local maxrate="$7"
  local bufsize="$8"
  local audio_bitrate="${9:-128k}"
  local include_audio="${10:-1}"
  local start_time="${11:-}"
  local duration="${12:-}"

  local input_height
  input_height="$(source_height "$input")"
  if (( input_height < height - 16 )); then
    rm -f "$out_dir/${label}.m3u8" "$out_dir/${label}.ts"
    return
  fi

  make_variant "$input" "$out_dir" "$label" "$height" "$crf" "$bitrate" "$maxrate" "$bufsize" "$audio_bitrate" "$include_audio" "$start_time" "$duration"
}

variant_stream_info() {
  local out_dir="$1"
  local label="$2"
  local bandwidth="$3"
  local average_bandwidth="$4"
  local include_audio="$5"

  [[ -s "$out_dir/${label}.m3u8" && -s "$out_dir/${label}.ts" ]] || return 0

  local resolution
  resolution="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$out_dir/${label}.ts" | sed -n '1p')"

  local codecs='avc1.4d401f'
  if [[ "$include_audio" == "1" ]]; then
    codecs='avc1.4d401f,mp4a.40.2'
  fi

  printf '#EXT-X-STREAM-INF:BANDWIDTH=%s,AVERAGE-BANDWIDTH=%s,RESOLUTION=%s,CODECS="%s"\n' "$bandwidth" "$average_bandwidth" "$resolution" "$codecs"
  printf '%s.m3u8\n' "$label"
}

write_master() {
  local out_dir="$1"
  local include_audio="${2:-1}"

  {
    cat <<EOF
#EXTM3U
#EXT-X-VERSION:6
EOF
    if [[ "$include_audio" == "1" ]]; then
      variant_stream_info "$out_dir" "480p" 900000 650000 1
      variant_stream_info "$out_dir" "720p" 1900000 1300000 1
      variant_stream_info "$out_dir" "1080p" 4500000 3000000 1
      variant_stream_info "$out_dir" "1440p" 9500000 7000000 1
      variant_stream_info "$out_dir" "2160p" 18000000 13000000 1
    else
      variant_stream_info "$out_dir" "480p" 700000 450000 0
      variant_stream_info "$out_dir" "720p" 1500000 900000 0
      variant_stream_info "$out_dir" "1080p" 3200000 2100000 0
      variant_stream_info "$out_dir" "1440p" 7000000 5000000 0
      variant_stream_info "$out_dir" "2160p" 12000000 8500000 0
    fi
  } > "$out_dir/master.m3u8"
}

make_set() {
  local slug="$1"
  local input="$2"

  local out_dir="$OUT_DIR/$slug"
  make_variant "$input" "$out_dir" "480p" 480 28 650k 900k 1800k 96k 1
  make_variant "$input" "$out_dir" "720p" 720 25 1400k 1900k 3800k 128k 1
  make_variant "$input" "$out_dir" "1080p" 1080 22 3300k 4500k 9000k 128k 1
  maybe_make_variant "$input" "$out_dir" "1440p" 1440 20 7000k 9500k 19000k 160k 1
  maybe_make_variant "$input" "$out_dir" "2160p" 2160 19 13000k 18000k 36000k 192k 1
  write_master "$out_dir" 1
}

make_loop() {
  local slug="$1"
  local input="$2"
  local start_time="${3:-}"
  local duration="${4:-}"

  local out_dir="$OUT_DIR/$slug"
  make_variant "$input" "$out_dir" "480p" 480 30 450k 700k 1400k 96k 0 "$start_time" "$duration"
  make_variant "$input" "$out_dir" "720p" 720 27 900k 1500k 3000k 96k 0 "$start_time" "$duration"
  make_variant "$input" "$out_dir" "1080p" 1080 24 2100k 3200k 6400k 96k 0 "$start_time" "$duration"
  maybe_make_variant "$input" "$out_dir" "1440p" 1440 22 5000k 7000k 14000k 96k 0 "$start_time" "$duration"
  maybe_make_variant "$input" "$out_dir" "2160p" 2160 21 8500k 12000k 24000k 96k 0 "$start_time" "$duration"
  write_master "$out_dir" 0
}

run_target() {
  case "$1" in
    chrysalism) make_set "chrysalism" "$ROOT_DIR/assets/movies/chrysalism full.mp4" ;;
    curtain-call) make_set "curtain-call" "$ROOT_DIR/assets/movies/Curtain Call (ROUGH) - Jason David Cox (1080p).mp4" ;;
    the-visitor) make_set "the-visitor" "$ROOT_DIR/assets/movies/The Visitor (FINE) - Jason David Cox (1080p).mp4" ;;
    beyond-blue-dawn) make_set "beyond-blue-dawn" "$ROOT_DIR/assets/movies/Beyond the Blue Dawn.mov" ;;
    fashion-business) make_set "fashion-business" "$ROOT_DIR/assets/movies/Fashion In Business Through the Looking Glass - Teaser - marley huggins (1080p).mp4" ;;
    home-hero) make_loop "home-hero" "$ROOT_DIR/assets/movies/chrysalism (2160p).mp4" 12 18 ;;
    films-hero) make_loop "films-hero" "$ROOT_DIR/assets/movies/second.mp4" ;;
    *) echo "Unknown target: $1" >&2; exit 1 ;;
  esac
}

if [[ "$#" -gt 0 ]]; then
  for target in "$@"; do
    run_target "$target"
  done
else
  run_target "chrysalism"
  run_target "curtain-call"
  run_target "the-visitor"
  run_target "beyond-blue-dawn"
  run_target "fashion-business"
  run_target "home-hero"
  run_target "films-hero"
fi
