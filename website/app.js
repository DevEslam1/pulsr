document.addEventListener('DOMContentLoaded', () => {
  // --- Audio Player State & Simulation ---
  const tracks = [
    {
      title: "Resonance (Hyperdrive Mix)",
      artist: "Aura Soundworks",
      album: "Cybernetic Echoes",
      duration: 218, // 3:38
      badge: "FLAC 24-bit / 96kHz",
      coverGradient: "linear-gradient(135deg, #1b2038 0%, #070913 100%)",
      lyrics: [
        { time: 0, text: "♪ Ambient synthesizer intro ♪" },
        { time: 12, text: "Frequencies pulse through the neon dark" },
        { time: 24, text: "A digital heartbeat ignites the spark" },
        { time: 36, text: "Lossless waves cascading down the wire" },
        { time: 48, text: "High-resolution dreams in acoustic fire" },
        { time: 60, text: "No telemetry, no tracking, just pure sound" },
        { time: 72, text: "Where pristine melodies are finally found" },
        { time: 88, text: "♪ Audiophile guitar solo & sub-bass drop ♪" },
        { time: 110, text: "Feel the resonance inside your mind" },
        { time: 130, text: "The cleanest offline groove you'll ever find" }
      ]
    },
    {
      title: "Midnight Tokyo Drift",
      artist: "Kavinsky Wave",
      album: "Analog Outrun 1984",
      duration: 194, // 3:14
      badge: "FLAC 24-bit / 192kHz",
      coverGradient: "linear-gradient(135deg, #2b1055 0%, #7597de 100%)",
      lyrics: [
        { time: 0, text: "♪ Synthesizer chords reverberate ♪" },
        { time: 15, text: "City lights reflected on the hood" },
        { time: 30, text: "Cruising fast through the neighborhood" },
        { time: 45, text: "10-band EQ dialed in so tight" },
        { time: 60, text: "Bass boost rattling through the night" }
      ]
    },
    {
      title: "Etherial Sanctuary",
      artist: "Luminary Ensemble",
      album: "Spatial Atmosphere",
      duration: 245, // 4:05
      badge: "ALAC 24-bit / 96kHz",
      coverGradient: "linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%)",
      lyrics: [
        { time: 0, text: "♪ Deep atmospheric soundscapes ♪" },
        { time: 20, text: "Breathe in the calm of harmonic space" },
        { time: 40, text: "Floating gently in time and place" },
        { time: 65, text: "Zero compression, lossless clarity" }
      ]
    }
  ];

  let currentTrackIdx = 0;
  let isPlaying = true;
  let currentTime = 42; // starts at 0:42
  let playbackInterval = null;

  // DOM Elements - Player
  const playBtn = document.getElementById('playPauseBtn');
  const prevBtn = document.getElementById('prevTrackBtn');
  const nextBtn = document.getElementById('nextTrackBtn');
  const favBtn = document.getElementById('favBtn');
  const songTitleEl = document.getElementById('songTitle');
  const songArtistEl = document.getElementById('songArtist');
  const qualityBadgeEl = document.getElementById('qualityBadge');
  const progressFill = document.getElementById('progressFill');
  const progressBar = document.getElementById('progressBar');
  const currentTimeEl = document.getElementById('currentTime');
  const totalDurationEl = document.getElementById('totalDuration');
  const albumArtBox = document.getElementById('albumArtBox');

  // Format Time Helper
  function formatTime(secs) {
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  // Load Track UI
  function loadTrack(idx) {
    const track = tracks[idx];
    songTitleEl.textContent = track.title;
    songArtistEl.textContent = `${track.artist} • ${track.album}`;
    qualityBadgeEl.textContent = track.badge;
    totalDurationEl.textContent = formatTime(track.duration);
    albumArtBox.style.background = track.coverGradient;
    updateProgress();
    renderLyrics();
  }

  function updateProgress() {
    const track = tracks[currentTrackIdx];
    const pct = (currentTime / track.duration) * 100;
    progressFill.style.width = `${pct}%`;
    currentTimeEl.textContent = formatTime(currentTime);
    updateLyricsActiveState();
  }

  // Toggle Play / Pause
  function togglePlay() {
    isPlaying = !isPlaying;
    if (isPlaying) {
      playBtn.innerHTML = '❚❚';
      startTimer();
    } else {
      playBtn.innerHTML = '▶';
      clearInterval(playbackInterval);
    }
  }

  function startTimer() {
    clearInterval(playbackInterval);
    playbackInterval = setInterval(() => {
      if (!isPlaying) return;
      const track = tracks[currentTrackIdx];
      currentTime += 1;
      if (currentTime >= track.duration) {
        currentTime = 0;
        currentTrackIdx = (currentTrackIdx + 1) % tracks.length;
        loadTrack(currentTrackIdx);
      }
      updateProgress();
    }, 1000);
  }

  if (playBtn) {
    playBtn.addEventListener('click', togglePlay);
    startTimer();
  }

  if (nextBtn) {
    nextBtn.addEventListener('click', () => {
      currentTrackIdx = (currentTrackIdx + 1) % tracks.length;
      currentTime = 0;
      loadTrack(currentTrackIdx);
    });
  }

  if (prevBtn) {
    prevBtn.addEventListener('click', () => {
      currentTrackIdx = (currentTrackIdx - 1 + tracks.length) % tracks.length;
      currentTime = 0;
      loadTrack(currentTrackIdx);
    });
  }

  if (favBtn) {
    favBtn.addEventListener('click', () => {
      favBtn.classList.toggle('active');
      favBtn.textContent = favBtn.classList.contains('active') ? '♥' : '♡';
    });
  }

  if (progressBar) {
    progressBar.addEventListener('click', (e) => {
      const rect = progressBar.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const width = rect.width;
      const track = tracks[currentTrackIdx];
      currentTime = Math.floor((clickX / width) * track.duration);
      updateProgress();
    });
  }

  // --- Real-time Visualizer Canvas ---
  const visualizerCanvas = document.getElementById('visualizerCanvas');
  if (visualizerCanvas) {
    const ctx = visualizerCanvas.getContext('2d');
    let animationFrameId;
    const numBars = 32;
    let barHeights = new Array(numBars).fill(10);

    function resizeCanvas() {
      visualizerCanvas.width = visualizerCanvas.offsetWidth * window.devicePixelRatio;
      visualizerCanvas.height = visualizerCanvas.offsetHeight * window.devicePixelRatio;
      ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
    }
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    function drawVisualizer() {
      const w = visualizerCanvas.offsetWidth;
      const h = visualizerCanvas.offsetHeight;
      ctx.clearRect(0, 0, w, h);

      const barWidth = (w / numBars) - 2;

      for (let i = 0; i < numBars; i++) {
        if (isPlaying) {
          // Dynamic frequency oscillation
          const target = Math.sin(Date.now() * 0.005 + i * 0.3) * (h * 0.38) + (h * 0.45) + (Math.random() * 8 - 4);
          barHeights[i] += (target - barHeights[i]) * 0.2;
        } else {
          barHeights[i] += (4 - barHeights[i]) * 0.1;
        }

        const barH = Math.max(3, barHeights[i]);
        const x = i * (barWidth + 2);
        const y = h - barH;

        // Gradient for bars
        const grad = ctx.createLinearGradient(0, y, 0, h);
        grad.addColorStop(0, '#00f2ff');
        grad.addColorStop(0.5, '#9b9ef5');
        grad.addColorStop(1, '#6c70dc');

        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.roundRect(x, y, barWidth, barH, [3, 3, 0, 0]);
        ctx.fill();
      }

      animationFrameId = requestAnimationFrame(drawVisualizer);
    }
    drawVisualizer();
  }

  // --- Theme Swatches ---
  const swatches = document.querySelectorAll('.swatch');
  const phoneFrame = document.getElementById('phoneFrame');
  const mockupGlow = document.getElementById('mockupGlow');

  const themePalettes = {
    aura: {
      bg: '#030a2e',
      border: 'rgba(255, 255, 255, 0.15)',
      glow: 'radial-gradient(circle, rgba(155, 158, 245, 0.35) 0%, rgba(0, 242, 255, 0.15) 50%, transparent 80%)'
    },
    cyan: {
      bg: '#041724',
      border: 'rgba(0, 242, 255, 0.3)',
      glow: 'radial-gradient(circle, rgba(0, 242, 255, 0.4) 0%, rgba(10, 80, 120, 0.2) 50%, transparent 80%)'
    },
    magenta: {
      bg: '#1f0717',
      border: 'rgba(255, 64, 129, 0.3)',
      glow: 'radial-gradient(circle, rgba(255, 64, 129, 0.4) 0%, rgba(120, 10, 80, 0.2) 50%, transparent 80%)'
    },
    amber: {
      bg: '#1f1304',
      border: 'rgba(255, 145, 0, 0.3)',
      glow: 'radial-gradient(circle, rgba(255, 145, 0, 0.4) 0%, rgba(120, 60, 10, 0.2) 50%, transparent 80%)'
    },
    amoled: {
      bg: '#000000',
      border: 'rgba(255, 255, 255, 0.2)',
      glow: 'radial-gradient(circle, rgba(255, 255, 255, 0.15) 0%, transparent 70%)'
    }
  };

  swatches.forEach(swatch => {
    swatch.addEventListener('click', () => {
      swatches.forEach(s => s.classList.remove('active'));
      swatch.classList.add('active');
      const themeKey = swatch.dataset.theme;
      const pal = themePalettes[themeKey];
      if (pal && phoneFrame && mockupGlow) {
        phoneFrame.style.background = pal.bg;
        phoneFrame.style.borderColor = pal.border;
        mockupGlow.style.background = pal.glow;
      }
    });
  });

  // --- Interactive Synced Lyrics Demo ---
  const lyricsContainer = document.getElementById('lyricsBox');

  function renderLyrics() {
    if (!lyricsContainer) return;
    const track = tracks[currentTrackIdx];
    lyricsContainer.innerHTML = '';
    track.lyrics.forEach((line, i) => {
      const div = document.createElement('div');
      div.className = 'lyrics-line';
      div.dataset.time = line.time;
      div.textContent = line.text;
      div.addEventListener('click', () => {
        currentTime = line.time;
        updateProgress();
      });
      lyricsContainer.appendChild(div);
    });
    updateLyricsActiveState();
  }

  function updateLyricsActiveState() {
    if (!lyricsContainer) return;
    const track = tracks[currentTrackIdx];
    const lines = lyricsContainer.querySelectorAll('.lyrics-line');
    let activeIdx = 0;

    track.lyrics.forEach((l, i) => {
      if (currentTime >= l.time) {
        activeIdx = i;
      }
    });

    lines.forEach((line, i) => {
      if (i === activeIdx) {
        line.classList.add('active');
        // Scroll ONLY the lyrics container without scrolling the main window!
        const lineOffset = line.offsetTop;
        const containerHeight = lyricsContainer.clientHeight;
        const targetScrollTop = lineOffset - (containerHeight / 2) + (line.clientHeight / 2);
        lyricsContainer.scrollTo({
          top: targetScrollTop,
          behavior: 'smooth'
        });
      } else {
        line.classList.remove('active');
      }
    });
  }

  // --- 10-Band Equalizer & AutoEQ Sandbox ---
  const eqCanvas = document.getElementById('eqCanvas');
  const eqSliders = document.querySelectorAll('.eq-slider');
  const presetButtons = document.querySelectorAll('.preset-btn');

  const eqPresets = {
    harman: {
      name: "Harman In-Ear Target",
      gains: [5.5, 3.8, 1.5, 0.0, -1.0, 1.2, 3.5, 4.0, 2.5, 1.5]
    },
    airpods: {
      name: "AirPods Pro (2nd Gen)",
      gains: [2.5, 1.8, 0.5, -0.5, 0.0, 1.0, -1.5, 0.5, 2.0, 2.8]
    },
    sony: {
      name: "Sony WH-1000XM5",
      gains: [-3.0, -1.5, 0.0, 1.5, 2.0, 2.5, 1.0, 2.0, 3.5, 1.0]
    },
    sennheiser: {
      name: "Sennheiser HD 600",
      gains: [4.5, 3.0, 1.0, 0.0, 0.0, -0.5, 1.0, 2.0, 1.5, -1.0]
    },
    bassboost: {
      name: "Club Bass Boost",
      gains: [8.0, 6.5, 4.5, 2.0, 0.0, 0.0, 0.5, 1.5, 2.5, 3.0]
    },
    flat: {
      name: "Flat / Neutral",
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    }
  };

  let currentGains = [...eqPresets.harman.gains];

  function drawEqCurve() {
    if (!eqCanvas) return;
    const ctx = eqCanvas.getContext('2d');
    const w = eqCanvas.offsetWidth;
    const h = eqCanvas.offsetHeight;

    eqCanvas.width = w * window.devicePixelRatio;
    eqCanvas.height = h * window.devicePixelRatio;
    ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

    ctx.clearRect(0, 0, w, h);

    // Draw 0dB reference line
    const zeroY = h / 2;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, zeroY);
    ctx.lineTo(w, zeroY);
    ctx.stroke();

    // Grid lines for +6dB / -6dB
    const dbScale = (h / 2) / 12; // 12dB max range

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
    ctx.beginPath();
    ctx.moveTo(0, zeroY - 6 * dbScale);
    ctx.lineTo(w, zeroY - 6 * dbScale);
    ctx.moveTo(0, zeroY + 6 * dbScale);
    ctx.lineTo(w, zeroY + 6 * dbScale);
    ctx.stroke();

    // Calculate curve points aligned to slider column centers
    const points = [];
    const sliderCols = document.querySelectorAll('.eq-band-col');
    const canvasRect = eqCanvas.getBoundingClientRect();

    currentGains.forEach((gain, i) => {
      let x = (i / (currentGains.length - 1)) * w;
      if (sliderCols.length === currentGains.length && canvasRect.width > 0) {
        const colRect = sliderCols[i].getBoundingClientRect();
        x = colRect.left + (colRect.width / 2) - canvasRect.left;
      }
      x = Math.max(0, Math.min(w, x));
      const y = Math.max(10, Math.min(h - 10, zeroY - (gain * dbScale)));
      points.push({ x, y });
    });

    if (points.length < 2) return;

    // Draw Smooth Catmull-Rom Spline (passes exactly through all nodes)
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);

    for (let i = 0; i < points.length - 1; i++) {
      const p0 = i > 0 ? points[i - 1] : points[i];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = (i < points.length - 2) ? points[i + 2] : p2;

      const cp1x = p1.x + (p2.x - p0.x) / 6;
      const cp1y = p1.y + (p2.y - p0.y) / 6;

      const cp2x = p2.x - (p3.x - p1.x) / 6;
      const cp2y = p2.y - (p3.y - p1.y) / 6;

      ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
    }

    // Gradient Stroke for Curve
    const strokeGrad = ctx.createLinearGradient(0, 0, w, 0);
    strokeGrad.addColorStop(0, '#00f2ff');
    strokeGrad.addColorStop(0.5, '#9b9ef5');
    strokeGrad.addColorStop(1, '#ff4081');

    ctx.strokeStyle = strokeGrad;
    ctx.lineWidth = 3.5;
    ctx.shadowColor = 'rgba(0, 242, 255, 0.6)';
    ctx.shadowBlur = 10;
    ctx.stroke();

    // Fill under curve
    ctx.lineTo(points[points.length - 1].x, h);
    ctx.lineTo(points[0].x, h);
    ctx.closePath();

    const fillGrad = ctx.createLinearGradient(0, 0, 0, h);
    fillGrad.addColorStop(0, 'rgba(155, 158, 245, 0.22)');
    fillGrad.addColorStop(1, 'rgba(155, 158, 245, 0.0)');
    ctx.fillStyle = fillGrad;
    ctx.shadowBlur = 0;
    ctx.fill();

    // Draw control nodes directly on top of the spline
    points.forEach((pt) => {
      // Outer glow
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0, 242, 255, 0.35)';
      ctx.fill();

      // Inner solid node
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = '#ffffff';
      ctx.shadowColor = '#00f2ff';
      ctx.shadowBlur = 6;
      ctx.fill();
    });
  }

  function applyPreset(presetKey) {
    const preset = eqPresets[presetKey];
    if (!preset) return;
    currentGains = [...preset.gains];

    eqSliders.forEach((slider, i) => {
      slider.value = currentGains[i];
      const dbDisplay = slider.parentElement.querySelector('.eq-band-db');
      if (dbDisplay) {
        const val = currentGains[i];
        dbDisplay.textContent = (val > 0 ? `+${val}` : `${val}`) + 'dB';
      }
    });

    drawEqCurve();
  }

  eqSliders.forEach((slider, idx) => {
    slider.addEventListener('input', (e) => {
      const val = parseFloat(e.target.value);
      currentGains[idx] = val;
      const dbDisplay = slider.parentElement.querySelector('.eq-band-db');
      if (dbDisplay) {
        dbDisplay.textContent = (val > 0 ? `+${val}` : `${val}`) + 'dB';
      }
      // Uncheck active presets
      presetButtons.forEach(btn => btn.classList.remove('active'));
      drawEqCurve();
    });
  });

  presetButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      presetButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      applyPreset(btn.dataset.preset);
    });
  });

  window.addEventListener('resize', drawEqCurve);
  // Initial draw
  setTimeout(() => {
    applyPreset('harman');
    loadTrack(0);
  }, 100);

  // --- FAQ Accordion ---
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    question.addEventListener('click', () => {
      const isOpen = item.classList.contains('active');
      faqItems.forEach(i => i.classList.remove('active'));
      if (!isOpen) {
        item.classList.add('active');
      }
    });
  });

  // --- Checksum Copy Utility ---
  const checksumPill = document.getElementById('checksumPill');
  if (checksumPill) {
    checksumPill.addEventListener('click', () => {
      const hash = checksumPill.dataset.hash || "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
      navigator.clipboard.writeText(hash).then(() => {
        const originalText = checksumPill.innerHTML;
        checksumPill.innerHTML = '<span>✔ SHA-256 Copied to clipboard!</span>';
        setTimeout(() => {
          checksumPill.innerHTML = originalText;
        }, 2500);
      });
    });
  }

  // --- Smooth Scroll Anchor Links & Mobile Menu Toggle ---
  const mobileToggle = document.querySelector('.mobile-toggle');
  const navLinks = document.querySelector('.nav-links');

  if (mobileToggle && navLinks) {
    mobileToggle.addEventListener('click', () => {
      navLinks.classList.toggle('mobile-open');
    });
  }

  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      const targetId = this.getAttribute('href');
      if (targetId === '#' || !targetId) return;
      const target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        const headerOffset = 80;
        const elementPosition = target.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

        window.scrollTo({
          top: offsetPosition,
          behavior: 'smooth'
        });

        if (navLinks && navLinks.classList.contains('mobile-open')) {
          navLinks.classList.remove('mobile-open');
        }
      }
    });
  });

  // --- Live GitHub Download Counter & Release Fetcher ---
  async function fetchGitHubStats() {
    try {
      const response = await fetch('https://api.github.com/repos/DevEslam1/pulsr/releases');
      if (!response.ok) return;
      const releases = await response.json();
      let totalDownloads = 0;
      let latestTag = 'v1.0.0';

      if (Array.isArray(releases) && releases.length > 0) {
        latestTag = releases[0].tag_name || 'v1.0.0';
        releases.forEach(rel => {
          if (rel.assets && Array.isArray(rel.assets)) {
            rel.assets.forEach(asset => {
              totalDownloads += (asset.download_count || 0);
            });
          }
        });
      }

      const downloadsBadge = document.getElementById('liveDownloadsBadge');
      if (downloadsBadge) {
        downloadsBadge.innerHTML = `📥 <strong>${totalDownloads.toLocaleString()}</strong> APK Downloads`;
      }

      const releaseTagEl = document.getElementById('releaseTagText');
      if (releaseTagEl) {
        releaseTagEl.textContent = `Release ${latestTag}`;
      }
    } catch (e) {
      console.log('GitHub API stats notice:', e);
    }
  }
  fetchGitHubStats();
});
