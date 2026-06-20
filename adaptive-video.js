(function () {
  function destroyHls(video) {
    if (video && video.__hls) {
      video.__hls.destroy();
      video.__hls = null;
    }
  }

  function attachAdaptiveVideo(video, hlsSrc, fallbackSrc) {
    if (!video) {
      return;
    }

    destroyHls(video);

    if (hlsSrc && video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = hlsSrc;
      video.load();
      return;
    }

    if (hlsSrc && window.Hls && window.Hls.isSupported()) {
      const hls = new window.Hls({
        capLevelToPlayerSize: true,
        startLevel: -1,
        maxBufferLength: 30,
        maxMaxBufferLength: 60
      });

      hls.loadSource(hlsSrc);
      hls.attachMedia(video);
      video.__hls = hls;
      return;
    }

    video.src = fallbackSrc;
    video.load();
  }

  function detachAdaptiveVideo(video) {
    destroyHls(video);
    if (video) {
      video.removeAttribute('src');
      video.load();
    }
  }

  window.attachAdaptiveVideo = attachAdaptiveVideo;
  window.detachAdaptiveVideo = detachAdaptiveVideo;
}());
