/* ==========================================================================
   PULSR MUSIC — Audiophile Offline Local Music Player
   Interactive Engine JavaScript
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
    'use strict';

    // 1. --- TOAST NOTIFICATIONS ---
    const toastBubble = document.getElementById('toastBubble');
    const toastMessage = document.getElementById('toastMessage');
    let toastTimeout = null;

    function showToast(msg) {
        if (!toastBubble || !toastMessage) return;
        toastMessage.textContent = msg;
        toastBubble.classList.add('show');
        clearTimeout(toastTimeout);
        toastTimeout = setTimeout(() => {
            toastBubble.classList.remove('show');
        }, 2800);
    }

    // 2. --- OS DETECTION & HERO CTA ---
    const detectUserOS = () => {
        const ua = navigator.userAgent;
        const isAndroid = /Android/i.test(ua);
        
        const detectorEl = document.getElementById('osDetectorLabel');
        const heroBtnText = document.getElementById('heroDetectedText');

        if (isAndroid) {
            if (detectorEl) detectorEl.textContent = '✓ Android Device Detected • Direct ARM64 (v8a) APK • 100% Offline';
            if (heroBtnText) heroBtnText.textContent = 'Download Android APK (ARM64)';
        } else {
            if (detectorEl) detectorEl.textContent = '✓ Android (5.0+) Live Build • Direct ARM64 (v8a) APK';
            if (heroBtnText) heroBtnText.textContent = 'Download Android APK (ARM64)';
        }
    };
    detectUserOS();

    // 3. --- THEME SWITCHER ---
    const htmlEl = document.documentElement;
    const themeToggle = document.getElementById('themeToggle');
    const themeDropdown = document.getElementById('themeDropdown');
    const themeOptions = document.querySelectorAll('.theme-opt');

    const savedTheme = localStorage.getItem('pulsr-landing-theme') || 'cyber';
    htmlEl.setAttribute('data-theme', savedTheme);
    updateActiveThemeOption(savedTheme);

    if (themeToggle && themeDropdown) {
        themeToggle.addEventListener('click', (e) => {
            e.stopPropagation();
            themeDropdown.classList.toggle('show');
        });

        document.addEventListener('click', () => {
            themeDropdown.classList.remove('show');
        });

        themeOptions.forEach(opt => {
            opt.addEventListener('click', () => {
                const themeVal = opt.dataset.themeVal;
                htmlEl.setAttribute('data-theme', themeVal);
                localStorage.setItem('pulsr-landing-theme', themeVal);
                updateActiveThemeOption(themeVal);
                themeDropdown.classList.remove('show');
                showToast(`Switched to ${opt.textContent.trim()} theme`);
                if (typeof drawEqCurve === 'function') drawEqCurve();
            });
        });
    }

    function updateActiveThemeOption(theme) {
        themeOptions.forEach(opt => {
            opt.classList.toggle('active', opt.dataset.themeVal === theme);
        });
    }

    // 4. --- MOBILE MENU TOGGLE ---
    const mobileToggle = document.getElementById('mobileToggle');
    const mobileMenu = document.getElementById('mobileMenu');
    if (mobileToggle && mobileMenu) {
        mobileToggle.addEventListener('click', (e) => {
            e.stopPropagation();
            const isOpen = mobileMenu.classList.toggle('open');
            mobileToggle.classList.toggle('open', isOpen);
            mobileToggle.setAttribute('aria-expanded', String(isOpen));
        });

        document.querySelectorAll('.mobile-link, .mobile-actions a, .mobile-actions button').forEach(link => {
            link.addEventListener('click', () => {
                mobileMenu.classList.remove('open');
                mobileToggle.classList.remove('open');
                mobileToggle.setAttribute('aria-expanded', 'false');
            });
        });

        document.addEventListener('click', (e) => {
            if (!mobileMenu.contains(e.target) && !mobileToggle.contains(e.target)) {
                mobileMenu.classList.remove('open');
                mobileToggle.classList.remove('open');
                mobileToggle.setAttribute('aria-expanded', 'false');
            }
        });
    }

    // 5. --- PLATFORM TABS ---
    const platTabs = document.querySelectorAll('.plat-tab');
    const platPanels = document.querySelectorAll('.plat-panel');

    function switchPlatformTab(platform) {
        platTabs.forEach(tab => {
            tab.classList.toggle('active', tab.dataset.platform === platform);
        });
        platPanels.forEach(panel => {
            panel.classList.toggle('active', panel.id === `panel-${platform}`);
        });
    }

    platTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            switchPlatformTab(tab.dataset.platform);
        });
    });

    // 6. --- HERO AUDIO PLAYER SIMULATION & SPECTRUM VISUALIZER ---
    const sampleTracks = [
        {
            title: "Resonance (Hyperdrive Mix)",
            artist: "Aura Soundworks • Cybernetic Echoes",
            bitrate: "FLAC 24-Bit / 192kHz",
            duration: 236 // 3:56
        },
        {
            title: "Midnight Tokyo Drift",
            artist: "Kavinsky Wave • Synth Outrun",
            bitrate: "FLAC 24-Bit / 96kHz",
            duration: 218 // 3:38
        },
        {
            title: "Etherial Sanctuary",
            artist: "Luminary Ensemble • Spatial Atmosphere",
            bitrate: "ALAC 24-Bit / 192kHz",
            duration: 260 // 4:20
        }
    ];

    let currentTrackIdx = 0;
    let isPlaying = true;
    let currentSeconds = 108; // 1:48

    const heroTrackTitle = document.getElementById('heroTrackTitle');
    const heroTrackArtist = document.getElementById('heroTrackArtist');
    const heroLiveBitrate = document.getElementById('heroLiveBitrate');
    const heroScrubberFill = document.getElementById('heroScrubberFill');
    const heroScrubberBar = document.getElementById('heroScrubberBar');
    const heroTimeCurrent = document.getElementById('heroTimeCurrent');
    const heroTimeTotal = document.getElementById('heroTimeTotal');
    const heroPlayBtn = document.getElementById('heroPlayBtn');
    const heroPlayIcon = document.getElementById('heroPlayIcon');
    const heroPrevBtn = document.getElementById('heroPrevBtn');
    const heroNextBtn = document.getElementById('heroNextBtn');
    const heroVisualizerCanvas = document.getElementById('heroVisualizerCanvas');

    function formatSecs(sec) {
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return `${m}:${s < 10 ? '0' : ''}${s}`;
    }

    function updateTrackDisplay() {
        const trk = sampleTracks[currentTrackIdx];
        if (heroTrackTitle) heroTrackTitle.textContent = trk.title;
        if (heroTrackArtist) heroTrackArtist.textContent = trk.artist;
        if (heroLiveBitrate) heroLiveBitrate.textContent = trk.bitrate;
        if (heroTimeTotal) heroTimeTotal.textContent = formatSecs(trk.duration);
        updateProgress();
    }

    function updateProgress() {
        const trk = sampleTracks[currentTrackIdx];
        const pct = (currentSeconds / trk.duration) * 100;
        if (heroScrubberFill) {
            heroScrubberFill.style.width = `${pct}%`;
            const thumb = heroScrubberFill.nextElementSibling;
            if (thumb) thumb.style.left = `${pct}%`;
        }
        if (heroTimeCurrent) heroTimeCurrent.textContent = formatSecs(currentSeconds);
    }

    if (heroPlayBtn) {
        heroPlayBtn.addEventListener('click', () => {
            isPlaying = !isPlaying;
            if (heroPlayIcon) {
                if (isPlaying) {
                    heroPlayIcon.innerHTML = '<rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect>';
                } else {
                    heroPlayIcon.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';
                }
            }
        });
    }

    if (heroPrevBtn) {
        heroPrevBtn.addEventListener('click', () => {
            currentTrackIdx = (currentTrackIdx - 1 + sampleTracks.length) % sampleTracks.length;
            currentSeconds = 0;
            updateTrackDisplay();
        });
    }

    if (heroNextBtn) {
        heroNextBtn.addEventListener('click', () => {
            currentTrackIdx = (currentTrackIdx + 1) % sampleTracks.length;
            currentSeconds = 0;
            updateTrackDisplay();
        });
    }

    if (heroScrubberBar) {
        heroScrubberBar.addEventListener('click', (e) => {
            const rect = heroScrubberBar.getBoundingClientRect();
            const clickX = e.clientX - rect.left;
            const pct = Math.max(0, Math.min(1, clickX / rect.width));
            const trk = sampleTracks[currentTrackIdx];
            currentSeconds = Math.round(pct * trk.duration);
            updateProgress();
        });
    }

    // Timer tick for player
    setInterval(() => {
        if (!isPlaying) return;
        const trk = sampleTracks[currentTrackIdx];
        currentSeconds++;
        if (currentSeconds >= trk.duration) {
            currentSeconds = 0;
            currentTrackIdx = (currentTrackIdx + 1) % sampleTracks.length;
            updateTrackDisplay();
        } else {
            updateProgress();
        }
    }, 1000);

    // Aura Palette Swatches
    const paletteDots = document.querySelectorAll('.palette-dot');
    const heroAlbumArt = document.getElementById('heroAlbumArt');
    paletteDots.forEach(dot => {
        dot.addEventListener('click', () => {
            paletteDots.forEach(d => d.classList.remove('active'));
            dot.classList.add('active');
            const pal = dot.dataset.palette;
            if (heroAlbumArt) {
                if (pal === 'cyan') heroAlbumArt.style.borderColor = '#00F2FF';
                if (pal === 'lavender') heroAlbumArt.style.borderColor = '#9B9EF5';
                if (pal === 'magenta') heroAlbumArt.style.borderColor = '#FF4081';
                if (pal === 'amber') heroAlbumArt.style.borderColor = '#FFAB00';
                if (pal === 'dark') heroAlbumArt.style.borderColor = 'rgba(255,255,255,0.2)';
            }
            showToast(`Aura Palette changed to ${dot.title}`);
        });
    });

    // Real-Time Canvas Spectrum Visualizer
    if (heroVisualizerCanvas) {
        const ctx = heroVisualizerCanvas.getContext('2d');
        const numBars = 32;
        let barHeights = Array(numBars).fill(10);

        const resizeVis = () => {
            heroVisualizerCanvas.width = heroVisualizerCanvas.parentElement.clientWidth * window.devicePixelRatio;
            heroVisualizerCanvas.height = heroVisualizerCanvas.parentElement.clientHeight * window.devicePixelRatio;
            ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
        };
        resizeVis();
        window.addEventListener('resize', resizeVis);

        function drawVisualizer() {
            const w = heroVisualizerCanvas.parentElement.clientWidth;
            const h = heroVisualizerCanvas.parentElement.clientHeight;
            ctx.clearRect(0, 0, w, h);

            const barWidth = (w / numBars) - 2;
            const primaryColor = getComputedStyle(document.documentElement).getPropertyValue('--primary-color').trim() || '#3B82F6';
            const cyanColor = getComputedStyle(document.documentElement).getPropertyValue('--accent-cyan').trim() || '#06B6D4';

            for (let i = 0; i < numBars; i++) {
                if (isPlaying) {
                    const target = 4 + Math.random() * (h - 8);
                    barHeights[i] += (target - barHeights[i]) * 0.25;
                } else {
                    barHeights[i] += (4 - barHeights[i]) * 0.1;
                }

                const grad = ctx.createLinearGradient(0, h, 0, 0);
                grad.addColorStop(0, primaryColor);
                grad.addColorStop(1, cyanColor);

                ctx.fillStyle = grad;
                ctx.fillRect(i * (barWidth + 2), h - barHeights[i], barWidth, barHeights[i]);
            }

            requestAnimationFrame(drawVisualizer);
        }
        drawVisualizer();
    }

    // 7. --- HERO LIVE SPARKLINE GRAPH ---
    const heroSparkLine = document.getElementById('heroSparkLine');
    const heroSparkArea = document.getElementById('heroSparkArea');

    if (heroSparkLine && heroSparkArea) {
        const W = 360, H = 70, POINTS = 20;
        let dataPoints = Array.from({ length: POINTS }, () => 35 + Math.random() * 20);

        const drawSparkline = () => {
            const step = W / (POINTS - 1);
            let path = '';
            dataPoints.forEach((val, i) => {
                const x = i * step;
                const y = H - (val / 70) * H;
                path += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ',' + y.toFixed(1) + ' ';
            });
            heroSparkLine.setAttribute('d', path);
            heroSparkArea.setAttribute('d', path + `L${W},${H} L0,${H} Z`);
        };

        drawSparkline();

        setInterval(() => {
            dataPoints.shift();
            const last = dataPoints[dataPoints.length - 1];
            const next = Math.min(60, Math.max(15, last + (Math.random() - 0.5) * 14));
            dataPoints.push(next);
            drawSparkline();
        }, 900);
    }

    // 8. --- 10-BAND EQUALIZER & AUTOEQ SANDBOX ---
    const eqCanvas = document.getElementById('eqCanvas');
    const eqSliders = document.querySelectorAll('.eq-slider');
    const eqPresetSelect = document.getElementById('eqPresetSelect');
    const resetEqBtn = document.getElementById('resetEqBtn');
    const eqActiveBadge = document.getElementById('eqActiveBadge');

    const eqPresets = {
        harman: [5.5, 3.8, 1.5, 0.0, -1.0, 1.2, 2.5, 4.0, 2.0, 1.0],
        airpods: [4.0, 2.5, 0.5, -0.5, 0.0, 2.0, 3.0, 1.5, -1.0, 0.5],
        sony: [1.5, 0.5, -1.0, -2.0, 0.0, 1.5, 3.5, 4.5, 2.0, 1.5],
        sennheiser: [6.0, 4.5, 2.0, 0.0, -0.5, 0.5, 1.0, 2.0, 1.5, 0.0],
        beyer: [3.0, 1.5, 0.0, -1.0, -1.5, 0.0, 1.5, -2.0, -3.5, -1.0],
        bass: [7.0, 5.5, 3.5, 1.0, 0.0, 0.0, 0.0, 1.0, 1.5, 2.0],
        vocal: [-2.0, -1.5, 0.0, 1.0, 2.5, 3.5, 4.0, 2.5, 1.0, 0.0],
        flat: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    };

    let currentBands = [...eqPresets.harman];

    function drawEqCurve() {
        if (!eqCanvas) return;
        const ctx = eqCanvas.getContext('2d');
        const parent = eqCanvas.parentElement;
        const width = parent.clientWidth;
        const height = parent.clientHeight;

        eqCanvas.width = width * window.devicePixelRatio;
        eqCanvas.height = height * window.devicePixelRatio;
        ctx.scale(window.devicePixelRatio, window.devicePixelRatio);

        ctx.clearRect(0, 0, width, height);

        // Draw horizontal 0dB grid line
        const midY = height / 2;
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(0, midY);
        ctx.lineTo(width, midY);
        ctx.stroke();
        ctx.setLineDash([]);

        // Calculate 10 points
        const numBands = 10;
        const step = width / (numBands + 1);
        const points = [];

        // Left anchor point
        points.push({ x: 0, y: midY - (currentBands[0] / 12) * (height * 0.4) });

        for (let i = 0; i < numBands; i++) {
            const x = (i + 1) * step;
            const y = midY - (currentBands[i] / 12) * (height * 0.4);
            points.push({ x, y });
        }

        // Right anchor point
        points.push({ x: width, y: midY - (currentBands[numBands - 1] / 12) * (height * 0.4) });

        // Catmull-Rom spline curve drawing
        const primaryColor = getComputedStyle(document.documentElement).getPropertyValue('--primary-color').trim() || '#3B82F6';
        const cyanColor = getComputedStyle(document.documentElement).getPropertyValue('--accent-cyan').trim() || '#06B6D4';

        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);

        for (let i = 0; i < points.length - 1; i++) {
            const p0 = points[i === 0 ? 0 : i - 1];
            const p1 = points[i];
            const p2 = points[i + 1];
            const p3 = points[i + 2 >= points.length ? points.length - 1 : i + 2];

            for (let t = 0; t <= 1; t += 0.05) {
                const t2 = t * t;
                const t3 = t2 * t;

                const x = 0.5 * (
                    (2 * p1.x) +
                    (-p0.x + p2.x) * t +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                    (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
                );
                const y = 0.5 * (
                    (2 * p1.y) +
                    (-p0.y + p2.y) * t +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                    (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3
                );
                ctx.lineTo(x, y);
            }
        }

        // Stroke line
        ctx.strokeStyle = cyanColor;
        ctx.lineWidth = 3;
        ctx.stroke();

        // Draw nodes
        for (let i = 1; i <= numBands; i++) {
            ctx.beginPath();
            ctx.arc(points[i].x, points[i].y, 4.5, 0, Math.PI * 2);
            ctx.fillStyle = '#FFFFFF';
            ctx.fill();
            ctx.strokeStyle = primaryColor;
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    function applyPreset(presetKey) {
        if (!eqPresets[presetKey]) return;
        currentBands = [...eqPresets[presetKey]];

        eqSliders.forEach((slider, idx) => {
            const val = currentBands[idx];
            slider.value = val;
            const dbEl = document.getElementById(`db-${idx}`);
            if (dbEl) {
                dbEl.textContent = (val > 0 ? `+${val}` : `${val}`) + 'dB';
            }
        });

        if (eqActiveBadge) {
            const sel = eqPresetSelect;
            const text = sel ? sel.options[sel.selectedIndex].text : presetKey;
            eqActiveBadge.textContent = `Target: ${text}`;
        }

        drawEqCurve();
    }

    eqSliders.forEach((slider) => {
        slider.addEventListener('input', (e) => {
            const idx = parseInt(e.target.dataset.band, 10);
            const val = parseFloat(e.target.value);
            currentBands[idx] = val;
            const dbEl = document.getElementById(`db-${idx}`);
            if (dbEl) {
                dbEl.textContent = (val > 0 ? `+${val}` : `${val}`) + 'dB';
            }
            if (eqActiveBadge) eqActiveBadge.textContent = 'Custom Tuning (User)';
            drawEqCurve();
        });
    });

    if (eqPresetSelect) {
        eqPresetSelect.addEventListener('change', (e) => {
            applyPreset(e.target.value);
            showToast(`Loaded ${eqPresetSelect.options[eqPresetSelect.selectedIndex].text}`);
        });
    }

    if (resetEqBtn) {
        resetEqBtn.addEventListener('click', () => {
            if (eqPresetSelect) eqPresetSelect.value = 'flat';
            applyPreset('flat');
            showToast('Equalizer reset to Flat 0dB');
        });
    }

    window.addEventListener('resize', drawEqCurve);
    drawEqCurve();

    // Enhancer pills toggle
    document.querySelectorAll('.enhancer-pill').forEach(pill => {
        pill.addEventListener('click', () => {
            pill.classList.toggle('active');
            showToast(`${pill.textContent.trim()} toggled`);
        });
    });

    // 9. --- SYNCED LYRICS SCROLLER ---
    const lyricsScrollBox = document.getElementById('lyricsScrollBox');
    const lyricLines = document.querySelectorAll('.lyric-line');
    const lyricOffsetMinus = document.getElementById('lyricOffsetMinus');
    const lyricOffsetPlus = document.getElementById('lyricOffsetPlus');
    let lyricOffset = 0;

    lyricLines.forEach(line => {
        line.addEventListener('click', () => {
            lyricLines.forEach(l => l.classList.remove('active-lyric'));
            line.classList.add('active-lyric');
            const sec = parseInt(line.dataset.time, 10);
            currentSeconds = sec;
            updateProgress();
            showToast(`Seeked audio to ${formatSecs(sec)}`);
        });
    });

    if (lyricOffsetMinus) {
        lyricOffsetMinus.addEventListener('click', () => {
            lyricOffset -= 50;
            const offsetTag = document.querySelector('.lyrics-offset-tag');
            if (offsetTag) offsetTag.textContent = `Offset: ${lyricOffset} ms`;
            showToast(`Lyrics offset adjusted: ${lyricOffset}ms`);
        });
    }

    if (lyricOffsetPlus) {
        lyricOffsetPlus.addEventListener('click', () => {
            lyricOffset += 50;
            const offsetTag = document.querySelector('.lyrics-offset-tag');
            if (offsetTag) offsetTag.textContent = `Offset: ${lyricOffset} ms`;
            showToast(`Lyrics offset adjusted: ${lyricOffset}ms`);
        });
    }

    // 10. --- CLIPBOARD COPY HANDLERS ---
    document.querySelectorAll('.copy-checksum-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const hash = btn.dataset.copy;
            if (hash) {
                navigator.clipboard.writeText(hash).then(() => {
                    showToast('SHA-256 Checksum copied!');
                });
            }
        });
    });

    // 11. --- SHARE MODAL ---
    const shareModalBackdrop = document.getElementById('shareModalBackdrop');
    const openShareModal = document.getElementById('openShareModal');
    const mobileShareBtn = document.getElementById('mobileShareBtn');
    const ctaShareBtn = document.getElementById('ctaShareBtn');
    const closeShareModal = document.getElementById('closeShareModal');
    const copyShareUrlBtn = document.getElementById('copyShareUrlBtn');
    const shareUrlInput = document.getElementById('shareUrlInput');

    const handleShare = () => {
        if (navigator.share) {
            navigator.share({
                title: 'Pulsr Music — Premium Offline Audiophile Player',
                text: 'Check out Pulsr Music — bit-perfect offline player with 10-band AutoEQ, synced lyrics, and zero telemetry!',
                url: window.location.href
            }).catch(() => {
                showShareModal();
            });
        } else {
            showShareModal();
        }
    };

    function showShareModal() {
        if (shareModalBackdrop) {
            shareModalBackdrop.classList.add('open');
            shareModalBackdrop.setAttribute('aria-hidden', 'false');
        }
    }

    function hideShareModal() {
        if (shareModalBackdrop) {
            shareModalBackdrop.classList.remove('open');
            shareModalBackdrop.setAttribute('aria-hidden', 'true');
        }
    }

    if (openShareModal) openShareModal.addEventListener('click', handleShare);
    if (mobileShareBtn) mobileShareBtn.addEventListener('click', handleShare);
    if (ctaShareBtn) ctaShareBtn.addEventListener('click', handleShare);
    if (closeShareModal) closeShareModal.addEventListener('click', hideShareModal);

    if (shareModalBackdrop) {
        shareModalBackdrop.addEventListener('click', (e) => {
            if (e.target === shareModalBackdrop) hideShareModal();
        });
    }

    if (copyShareUrlBtn && shareUrlInput) {
        copyShareUrlBtn.addEventListener('click', () => {
            navigator.clipboard.writeText(shareUrlInput.value).then(() => {
                showToast('Pulsr share link copied to clipboard!');
                copyShareUrlBtn.textContent = 'Copied!';
                setTimeout(() => { copyShareUrlBtn.textContent = 'Copy Link'; }, 2000);
            });
        });
    }

    // 12. --- FAQ ACCORDION ---
    document.querySelectorAll('.faq-item').forEach(item => {
        const questionBtn = item.querySelector('.faq-question');
        if (questionBtn) {
            questionBtn.addEventListener('click', () => {
                const isOpen = item.classList.contains('open');
                document.querySelectorAll('.faq-item').forEach(other => other.classList.remove('open'));
                if (!isOpen) item.classList.add('open');
            });
        }
    });

    // 13. --- GITHUB STATS & DYNAMIC RELEASES ARCHIVE ---
    async function fetchGitHubStats() {
        try {
            const res = await fetch('https://api.github.com/repos/DevEslam1/pulsr');
            if (res.ok) {
                const data = await res.json();
                const starEl = document.getElementById('githubStars');
                if (starEl && data.stargazers_count !== undefined) {
                    starEl.textContent = `★ ${(data.stargazers_count / 1000).toFixed(1)}k`;
                }
            }

            const relRes = await fetch('https://api.github.com/repos/DevEslam1/pulsr/releases');
            if (relRes.ok) {
                const releases = await relRes.json();
                let totalDownloads = 0;
                const archiveList = document.getElementById('versionsArchiveList');

                if (Array.isArray(releases) && releases.length > 0) {
                    if (archiveList) archiveList.innerHTML = '';

                    // Update main download links with latest ARM64 asset
                    const latestRel = releases[0];
                    if (latestRel && latestRel.assets && Array.isArray(latestRel.assets)) {
                        const apkAssets = latestRel.assets.filter(a => a.name.endsWith('.apk'));
                        const arm64Asset = apkAssets.find(a => a.name.includes('arm64-v8a') || a.name.includes('a8v')) || apkAssets[0];
                        if (arm64Asset) {
                            const heroAutoBtn = document.getElementById('heroAutoDownloadBtn');
                            if (heroAutoBtn) {
                                heroAutoBtn.href = arm64Asset.browser_download_url;
                                heroAutoBtn.setAttribute('download', arm64Asset.name);
                            }
                            const autoBtn = document.getElementById('autoDownloadBtn');
                            if (autoBtn) {
                                autoBtn.href = arm64Asset.browser_download_url;
                                autoBtn.setAttribute('download', arm64Asset.name);
                            }
                        }
                    }

                    releases.forEach((rel, index) => {
                        let rawTag = rel.tag_name || 'v1.0.0';
                        const tag = rawTag.replace(/^Pulsr_Music_/i, '').replace(/^Pulsr_/i, '');
                        const isLatest = index === 0;
                        const pubDate = rel.published_at ? new Date(rel.published_at).toLocaleDateString() : '';

                        let apkButtonsHtml = '';
                        if (rel.assets && Array.isArray(rel.assets)) {
                            const apkAssets = rel.assets.filter(a => a.name.endsWith('.apk'));
                            if (apkAssets.length > 0) {
                                apkAssets.forEach(apk => {
                                    totalDownloads += (apk.download_count || 0);
                                    let label = apk.name;
                                    let isPrimary = false;
                                    if (label.includes('arm64-v8a') || label.includes('a8v')) {
                                        label = 'ARM64 (v8a)';
                                        isPrimary = true;
                                    } else if (label.includes('armeabi-v7a') || label.includes('a7v')) {
                                        label = 'ARMv7 (a7v)';
                                    } else if (label.includes('x86_64') || label.includes('x86')) {
                                        label = 'x86_64';
                                    } else {
                                        label = 'APK Build';
                                    }

                                    apkButtonsHtml += `
                                        <a href="${apk.browser_download_url}" download="${apk.name}" class="version-apk-btn ${isPrimary ? 'primary-apk' : ''}">
                                            ⬇ ${label}
                                        </a>
                                    `;
                                });
                            }
                        }

                        if (!apkButtonsHtml) {
                            apkButtonsHtml = `
                                <a href="${rel.html_url}" target="_blank" class="version-apk-btn primary-apk">
                                    ⬇ GitHub Release
                                </a>
                            `;
                        }

                        if (archiveList) {
                            const row = document.createElement('div');
                            row.className = 'version-release-row';
                            row.innerHTML = `
                                <div class="version-release-header">
                                    <span class="version-tag-pill">${tag}</span>
                                    ${isLatest ? '<span class="version-badge-latest">⚡ Latest Release</span>' : ''}
                                    ${pubDate ? `<span class="version-date-text">${pubDate}</span>` : ''}
                                </div>
                                <div class="version-downloads-actions">
                                    ${apkButtonsHtml}
                                    <a href="${rel.html_url}" target="_blank" class="version-apk-btn" style="color: var(--text-muted);" title="View changelog">
                                        Notes ↗
                                    </a>
                                </div>
                            `;
                            archiveList.appendChild(row);
                        }
                    });

                    const liveDownloadsBadge = document.getElementById('liveDownloadsBadge');
                    if (liveDownloadsBadge) {
                        liveDownloadsBadge.textContent = `📥 ${totalDownloads.toLocaleString()} Downloads`;
                    }
                }
            }
        } catch (e) {
            console.warn('GitHub API fallback active:', e);
        }
    }
    fetchGitHubStats();

    // 14. --- SCROLL BEHAVIOR & REVEALS ---
    const navHeader = document.getElementById('navHeader');
    const backToTop = document.getElementById('backToTop');
    const revealEls = document.querySelectorAll('.reveal');
    const sections = document.querySelectorAll('section[id]');
    const navLinks = document.querySelectorAll('.nav-link');

    window.addEventListener('scroll', () => {
        const scrollY = window.scrollY;
        if (navHeader) navHeader.classList.toggle('scrolled', scrollY > 20);
        if (backToTop) backToTop.classList.toggle('visible', scrollY > 400);

        let currentSection = '';
        sections.forEach(sec => {
            const top = sec.offsetTop - 140;
            const height = sec.offsetHeight;
            if (scrollY >= top && scrollY < top + height) {
                currentSection = sec.getAttribute('id');
            }
        });

        if (currentSection) {
            navLinks.forEach(link => {
                const href = link.getAttribute('href');
                link.classList.toggle('active', href === `#${currentSection}`);
            });
        }
    }, { passive: true });

    if (backToTop) {
        backToTop.addEventListener('click', () => {
            window.scrollTo({ top: 0, behavior: 'smooth' });
        });
    }

    if ('IntersectionObserver' in window) {
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('visible');
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.08 });

        revealEls.forEach(el => observer.observe(el));
    } else {
        revealEls.forEach(el => el.classList.add('visible'));
    }

    // Direct download toast handler for all APK download links
    document.querySelectorAll('a[download]').forEach(link => {
        link.addEventListener('click', () => {
            showToast('Starting Pulsr APK download...');
        });
    });
});
