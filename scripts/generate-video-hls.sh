#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/movies/hls"

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

  mkdir -p "$out_dir"

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

  ffmpeg -y -i "$input" \
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

write_master() {
  local out_dir="$1"
  local aspect="$2"

  cat > "$out_dir/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-STREAM-INF:BANDWIDTH=900000,AVERAGE-BANDWIDTH=650000,RESOLUTION=${aspect}x480,CODECS="avc1.4d401f,mp4a.40.2"
480p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1900000,AVERAGE-BANDWIDTH=1300000,RESOLUTION=${aspect}x720,CODECS="avc1.4d401f,mp4a.40.2"
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4500000,AVERAGE-BANDWIDTH=3000000,RESOLUTION=${aspect}x1080,CODECS="avc1.4d401f,mp4a.40.2"
1080p.m3u8
EOF
}

write_master_no_audio() {
  local out_dir="$1"
  local aspect="$2"

  cat > "$out_dir/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-STREAM-INF:BANDWIDTH=700000,AVERAGE-BANDWIDTH=450000,RESOLUTION=${aspect}x480,CODECS="avc1.4d401f"
480p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,AVERAGE-BANDWIDTH=900000,RESOLUTION=${aspect}x720,CODECS="avc1.4d401f"
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,AVERAGE-BANDWIDTH=2100000,RESOLUTION=${aspect}x1080,CODECS="avc1.4d401f"
1080p.m3u8
EOF
}

make_set() {
  local slug="$1"
  local input="$2"
  local aspect="$3"

  local out_dir="$OUT_DIR/$slug"
  make_variant "$input" "$out_dir" "480p" 480 28 650k 900k 1800k 96k 1
  make_variant "$input" "$out_dir" "720p" 720 25 1400k 1900k 3800k 128k 1
  make_variant "$input" "$out_dir" "1080p" 1080 22 3300k 4500k 9000k 128k 1
  write_master "$out_dir" "$aspect"
}

make_loop() {
  local slug="$1"
  local input="$2"
  local aspect="$3"

  local out_dir="$OUT_DIR/$slug"
  make_variant "$input" "$out_dir" "480p" 480 30 450k 700k 1400k 96k 0
  make_variant "$input" "$out_dir" "720p" 720 27 900k 1500k 3000k 96k 0
  make_variant "$input" "$out_dir" "1080p" 1080 24 2100k 3200k 6400k 96k 0
  write_master_no_audio "$out_dir" "$aspect"
}

make_set "chrysalism" "$ROOT_DIR/assets/movies/chrysalism full.mp4" 1680
make_set "curtain-call" "$ROOT_DIR/assets/movies/Curtain Call (ROUGH) - Jason David Cox (1080p).mp4" 1920
make_set "the-visitor" "$ROOT_DIR/assets/movies/The Visitor (FINE) - Jason David Cox (1080p).mp4" 1920
make_set "beyond-blue-dawn" "$ROOT_DIR/assets/movies/Beyond the Blue Dawn.mov" 1920
make_set "fashion-business" "$ROOT_DIR/assets/movies/Fashion In Business Through the Looking Glass - Teaser - marley huggins (1080p).mp4" 1920
make_loop "home-hero" "$ROOT_DIR/assets/movies/web/home-hero-720.mp4" 1680
make_loop "films-hero" "$ROOT_DIR/assets/movies/second.mp4" 1680
