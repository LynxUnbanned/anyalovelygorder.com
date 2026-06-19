/**
 * film-effects.js
 * Cinematic 35mm film frame aesthetic for Anya Gorder's website.
 * - Canvas-based animated film grain
 * - 35mm film strip borders with sprocket holes + edge data text
 * - Subtle warm light leaks
 */

(function () {
  "use strict";

  /* ── 1. CANVAS FILM GRAIN ─────────────────────────────────────────── */
  function initGrain() {
    const canvas = document.createElement("canvas");
    canvas.id = "film-grain";
    canvas.style.cssText = [
      "position:fixed", "top:0", "left:0",
      "width:100vw", "height:100vh",
      "pointer-events:none", "z-index:9990",
      "opacity:0.04", "mix-blend-mode:screen"
    ].join(";");
    document.body.appendChild(canvas);

    const ctx = canvas.getContext("2d");
    let w, h;

    function resize() {
      w = canvas.width = window.innerWidth;
      h = canvas.height = window.innerHeight;
    }
    resize();
    window.addEventListener("resize", resize);

    function drawGrain() {
      const d = ctx.createImageData(w, h);
      const px = d.data;
      for (let i = 0; i < px.length; i += 4) {
        const v = (Math.random() * 255) | 0;
        px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255;
      }
      ctx.putImageData(d, 0, 0);
      requestAnimationFrame(drawGrain);
    }
    drawGrain();
  }

  /* ── 2. FILM STRIP BORDERS (SCROLLING WITH PAGE) ─────────────────── */
  function initFilmStrips() {
    const STRIP_W = 54;
    const HOLE_W = 18;
    const HOLE_H = 12;
    const HOLE_GAP = 32;

    /* Edge-data strings */
    const edgeText = "KODAK VISION3  500T  5219  ●  ";
    const frameNums = "0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 ";

    const style = `
      .film-strip {
        position: absolute;
        top: 0;
        bottom: 0;
        width: ${STRIP_W}px;
        background: #0a0a0a;
        z-index: 9988;
        pointer-events: none;
        overflow: hidden;
        display: flex;
        flex-direction: column;
        box-sizing: border-box;
        border-color: #2a2a2a;
        border-style: solid;
      }
      .film-strip.left  {
        left: 0;
        border-right-width: 1px;
        border-left-width: 0;
        border-top-width: 0;
        border-bottom-width: 0;
      }
      .film-strip.right {
        right: 0;
        border-left-width: 1px;
        border-right-width: 0;
        border-top-width: 0;
        border-bottom-width: 0;
      }
      .film-edge-data {
        position: absolute;
        top: 0;
        width: 14px;
        height: 100%;
        white-space: nowrap;
        writing-mode: vertical-rl;
        text-orientation: mixed;
        font-family: "Courier New", monospace;
        font-size: 7px;
        letter-spacing: 2px;
        color: #c8922a;
        opacity: 0.75;
        user-select: none;
        line-height: 14px;
        overflow: hidden;
      }
      .film-strip.left  .film-edge-data { left: 3px; transform: rotate(180deg); }
      .film-strip.right .film-edge-data { right: 3px; }
      
      .film-frame-num {
        position: absolute;
        top: 0;
        width: 10px;
        height: 100%;
        white-space: nowrap;
        writing-mode: vertical-rl;
        font-family: "Courier New", monospace;
        font-size: 6px;
        letter-spacing: 3px;
        color: #5a4010;
        opacity: 0.6;
        user-select: none;
        line-height: 10px;
        overflow: hidden;
      }
      .film-strip.left  .film-frame-num { right: 4px; transform: rotate(180deg); }
      .film-strip.right .film-frame-num { left: 4px; }
      
      .film-holes {
        position: absolute;
        top: 0;
        bottom: 0;
        width: ${HOLE_W + 8}px;
        background-image: url("data:image/svg+xml;charset=utf-8,%3Csvg%20width%3D%2218%22%20height%3D%2244%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%3Crect%20x%3D%220%22%20y%3D%2216%22%20width%3D%2218%22%20height%3D%2212%22%20rx%3D%223%22%20fill%3D%22%23000%22%20stroke%3D%22%233a3a3a%22%20stroke-width%3D%221%22%2F%3E%3C%2Fsvg%3E");
        background-repeat: repeat-y;
        background-position: center top;
      }
      .film-strip.left  .film-holes { right: 16px; }
      .film-strip.right .film-holes { left: 16px; }
      
      .film-strip::after {
        content: "";
        position: absolute;
        top: 0;
        height: 100%;
        width: 1px;
        background: linear-gradient(to bottom, transparent 0%, #c8922a44 20%, #c8922a88 50%, #c8922a44 80%, transparent 100%);
      }
      .film-strip.left::after  { right: 0; }
      .film-strip.right::after { left: 0; }

      @media (max-width: 760px) {
        .film-strip {
          display: none;
        }
      }
    `;

    const styleEl = document.createElement("style");
    styleEl.textContent = style;
    document.head.appendChild(styleEl);

    ["left", "right"].forEach((side) => {
      const strip = document.createElement("div");
      strip.className = `film-strip ${side}`;

      const ed = document.createElement("div");
      ed.className = "film-edge-data";
      ed.textContent = edgeText.repeat(1000); /* Large repeat to cover scroll height */
      strip.appendChild(ed);

      const fn = document.createElement("div");
      fn.className = "film-frame-num";
      fn.textContent = frameNums.repeat(1000);
      strip.appendChild(fn);

      const holesCol = document.createElement("div");
      holesCol.className = "film-holes";
      strip.appendChild(holesCol);

      document.body.appendChild(strip);
    });
  }

  /* ── 3. SUBTLE LIGHT LEAKS ────────────────────────────────────────── */
  function initLightLeaks() {
    const el = document.createElement("div");
    el.id = "film-light-leaks";
    el.style.cssText = [
      "position:fixed", "inset:0",
      "pointer-events:none", "z-index:9989",
      "mix-blend-mode:screen"
    ].join(";");

    const leakStyle = `
      #film-light-leaks::before {
        content: "";
        position: absolute;
        top: -20%; left: -10%;
        width: 55%; height: 60%;
        background: radial-gradient(ellipse at center,
          rgba(255,140,30,0.12) 0%, transparent 70%
        );
        filter: blur(60px);
        animation: leak1 18s ease-in-out infinite alternate;
      }
      #film-light-leaks::after {
        content: "";
        position: absolute;
        bottom: -15%; right: -10%;
        width: 50%; height: 55%;
        background: radial-gradient(ellipse at center,
          rgba(200,30,10,0.09) 0%, transparent 70%
        );
        filter: blur(80px);
        animation: leak2 22s ease-in-out infinite alternate;
      }
      @keyframes leak1 {
        0%   { transform: translate(0,0)       scale(1);    opacity:.8; }
        50%  { transform: translate(40px,30px)  scale(1.2); opacity:1;  }
        100% { transform: translate(-20px,50px) scale(.9);  opacity:.7; }
      }
      @keyframes leak2 {
        0%   { transform: translate(0,0)         scale(1);    opacity:.7; }
        50%  { transform: translate(-50px,-30px)  scale(1.15); opacity:.9; }
        100% { transform: translate(30px,-50px)   scale(.95); opacity:.6; }
      }
    `;

    const styleEl = document.createElement("style");
    styleEl.textContent = leakStyle;
    document.head.appendChild(styleEl);
    document.body.appendChild(el);
  }

  /* ── INIT ─────────────────────────────────────────────────────────── */
  function init() {
    initGrain();
    initFilmStrips();
    initLightLeaks();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
