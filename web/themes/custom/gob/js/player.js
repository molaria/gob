/**
 * @file
 * Voice-part mixer popup for the note register.
 *
 * Every Lyssna button carries its playlist as JSON (label + url per
 * audio file, in node field order). The mixer plays all parts in sync
 * through Web Audio so a member can raise her own voice part and
 * lower the others. One shared <dialog> is built on first use.
 *
 * Web Audio is started from the play click, which satisfies the
 * autoplay policies on iOS and Android.
 *
 * The mixed output is routed into a hidden <audio> element (through a
 * MediaStreamAudioDestinationNode) so mobile browsers treat playback as
 * real media: audible with the iPhone silent switch on, kept alive when
 * the screen locks, and shown on the lock screen via Media Session.
 * Without MediaStream support the output goes straight to the speakers.
 */
(function (Drupal, once) {
  'use strict';

  let ctx = null;
  let dialog = null;
  let streamDest = null; // MediaStreamAudioDestinationNode, or null
  let audioEl = null; // hidden <audio> playing streamDest's stream
  let directOutput = false; // true when the stream route failed or is unavailable
  let current = null; // { tracks, buffers, gains, sources, startedAt, offset, playing, raf, duration, solo }

  function formatTime(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    return Math.floor(s / 60) + '.' + String(s % 60).padStart(2, '0');
  }

  function buildDialog() {
    dialog = document.createElement('dialog');
    dialog.className = 'gob-player';
    dialog.innerHTML =
      '<div class="gob-player__head">' +
      '  <h2 class="gob-player__title"></h2>' +
      '  <button type="button" class="gob-player__close">Stäng</button>' +
      '</div>' +
      '<div class="gob-player__status" hidden></div>' +
      '<div class="gob-player__master" hidden>' +
      '  <button type="button" class="gob-player__play" aria-label="Spela">' +
      '    <svg class="gob-player__icon-play" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>' +
      '    <svg class="gob-player__icon-pause" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" hidden><path d="M7 5h4v14H7zM13 5h4v14h-4z"/></svg>' +
      '  </button>' +
      '  <input class="gob-player__progress" type="range" min="0" max="1000" value="0" aria-label="Position i låten">' +
      '  <span class="gob-player__time">0.00 / 0.00</span>' +
      '</div>' +
      '<div class="gob-player__tracks"></div>';
    document.body.appendChild(dialog);

    dialog.querySelector('.gob-player__close').addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', stopAll);
    // Click on the backdrop closes too - the dialog itself covers the
    // inner surface, so a click landing on the dialog element is a
    // click outside it.
    dialog.addEventListener('click', (e) => {
      if (e.target === dialog) {
        dialog.close();
      }
    });

    dialog.querySelector('.gob-player__play').addEventListener('click', togglePlay);
    dialog.querySelector('.gob-player__progress').addEventListener('input', (e) => {
      if (!current || !current.duration) {
        return;
      }
      seek((e.target.value / 1000) * current.duration);
    });
  }

  function stopSources() {
    if (current && current.sources) {
      current.sources.forEach((s) => {
        // Detach first: stop() fires "ended" too, and only a natural
        // end of the song may be treated as one.
        s.onended = null;
        try { s.stop(); } catch (e) { /* already stopped */ }
      });
      current.sources = null;
    }
  }

  function stopAll() {
    stopSources();
    if (current) {
      cancelAnimationFrame(current.raf);
      current.playing = false;
      current = null;
    }
    if (audioEl) {
      audioEl.pause();
    }
    clearMediaSession();
    if (ctx && ctx.state === 'running') {
      ctx.suspend();
    }
  }

  // Where the gain nodes send their sound.
  function outputNode() {
    return streamDest && !directOutput ? streamDest : ctx.destination;
  }

  // Safety net: if the <audio> element refuses to play, the stream route
  // would be silent, so send the sound straight to the speakers instead.
  function fallBackToDirectOutput() {
    directOutput = true;
    if (current && current.gains) {
      current.gains.forEach((g) => {
        g.disconnect();
        g.connect(ctx.destination);
      });
    }
  }

  function startAudioElement() {
    if (!audioEl) {
      return;
    }
    const result = audioEl.play();
    if (result && result.catch) {
      result.catch(fallBackToDirectOutput);
    }
  }

  // One-time setup of the audio context and the media route.
  function ensureContext() {
    if (ctx) {
      return;
    }
    ctx = new (window.AudioContext || window.webkitAudioContext)();

    // Make iOS treat the page as media playback, not ambient sound.
    if (navigator.audioSession) {
      try { navigator.audioSession.type = 'playback'; } catch (e) { /* unsupported value */ }
    }

    if (ctx.createMediaStreamDestination) {
      streamDest = ctx.createMediaStreamDestination();
      audioEl = document.createElement('audio');
      audioEl.hidden = true;
      audioEl.playsInline = true;
      audioEl.srcObject = streamDest.stream;
      document.body.appendChild(audioEl);
      // The system (lock screen, headset button) can pause the element.
      audioEl.addEventListener('pause', () => {
        if (current && current.playing) {
          pausePlayback();
        }
      });
    }
    else {
      directOutput = true;
    }

    ctx.addEventListener('statechange', checkRunning);
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && current && current.duration) {
        updateProgress(position());
        checkRunning();
      }
    });

    if ('mediaSession' in navigator) {
      const session = navigator.mediaSession;
      const handlers = {
        play: play,
        pause: pausePlayback,
        seekto: (d) => { if (current && current.duration && d.seekTime != null) { seek(d.seekTime); } },
        seekbackward: (d) => { if (current && current.duration) { seek(Math.max(0, position() - (d.seekOffset || 10))); } },
        seekforward: (d) => { if (current && current.duration) { seek(Math.min(current.duration, position() + (d.seekOffset || 10))); } },
      };
      Object.keys(handlers).forEach((action) => {
        try { session.setActionHandler(action, handlers[action]); } catch (e) { /* action unsupported */ }
      });
    }
  }

  function clearMediaSession() {
    if (!('mediaSession' in navigator)) {
      return;
    }
    try {
      navigator.mediaSession.playbackState = 'none';
      navigator.mediaSession.metadata = null;
    } catch (e) { /* ignore */ }
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator) || !current || !current.duration) {
      return;
    }
    const session = navigator.mediaSession;
    try {
      session.playbackState = current.playing ? 'playing' : 'paused';
      session.setPositionState({
        duration: current.duration,
        playbackRate: 1,
        position: Math.min(Math.max(position(), 0), current.duration),
      });
    } catch (e) { /* position state unsupported */ }
  }

  // The system pauses the context during calls, Siri and screen lock.
  // If playback should be running but is not, try to resume, and if that
  // fails show the paused state so the UI never claims it is playing.
  function checkRunning() {
    if (!current || !current.playing) {
      return;
    }
    if (ctx.state === 'running') {
      if (audioEl && audioEl.paused) {
        startAudioElement();
      }
      return;
    }
    const giveUp = () => {
      if (current && current.playing && ctx.state !== 'running') {
        pausePlayback();
      }
    };
    // resume() may stay pending during an interruption, so do not wait for it.
    ctx.resume().then(() => { if (ctx.state !== 'running') { giveUp(); } }, giveUp);
    setTimeout(giveUp, 1500);
  }

  function effectiveGain(i) {
    const t = current.tracks[i];
    const soloActive = current.solo.some(Boolean);
    if (t.muted || (soloActive && !current.solo[i])) {
      return 0;
    }
    return t.volume;
  }

  function applyGains() {
    current.tracks.forEach((t, i) => {
      current.gains[i].gain.value = effectiveGain(i);
      const row = current.rows[i];
      row.classList.toggle('is-muted', effectiveGain(i) === 0);
      row.querySelector('.gob-player__mute').classList.toggle('is-on', t.muted);
      row.querySelector('.gob-player__solo').classList.toggle('is-on', current.solo[i]);
    });
  }

  function startSources(offset) {
    stopSources();
    current.sources = current.buffers.map((buffer, i) => {
      const src = ctx.createBufferSource();
      src.buffer = buffer;
      src.connect(current.gains[i]);
      return src;
    });
    const when = ctx.currentTime + 0.05;
    current.sources.forEach((s) => s.start(when, offset));
    current.startedAt = when - offset;

    // Song end is detected from the longest source, not from the
    // animation loop, which does not run while the screen is off.
    const sources = current.sources;
    let longest = 0;
    current.buffers.forEach((b, i) => {
      if (b.duration > current.buffers[longest].duration) {
        longest = i;
      }
    });
    sources[longest].onended = () => {
      if (current && current.sources === sources && current.playing) {
        songEnded();
      }
    };
  }

  function songEnded() {
    cancelAnimationFrame(current.raf);
    current.playing = false;
    current.offset = 0;
    stopSources();
    if (audioEl) {
      audioEl.pause();
    }
    updateProgress(0);
    setPlayIcon(false);
    updateMediaSession();
  }

  function position() {
    if (!current) {
      return 0;
    }
    return current.playing ? Math.min(ctx.currentTime - current.startedAt, current.duration) : current.offset;
  }

  function tick() {
    if (!current || !current.playing) {
      return;
    }
    // Drawing only; the end of the song is handled by onended.
    updateProgress(position());
    current.raf = requestAnimationFrame(tick);
  }

  function updateProgress(pos) {
    dialog.querySelector('.gob-player__progress').value = current.duration ? Math.round((pos / current.duration) * 1000) : 0;
    dialog.querySelector('.gob-player__time').textContent = formatTime(pos) + ' / ' + formatTime(current.duration);
  }

  function setPlayIcon(playing) {
    dialog.querySelector('.gob-player__icon-play').hidden = playing;
    dialog.querySelector('.gob-player__icon-pause').hidden = !playing;
    dialog.querySelector('.gob-player__play').setAttribute('aria-label', playing ? 'Pausa' : 'Spela');
  }

  function play() {
    if (!current || !current.buffers || current.playing) {
      return;
    }
    if (ctx.state !== 'running') {
      ctx.resume();
    }
    // Must run inside the user gesture (button or media key).
    startAudioElement();
    if (current.offset >= current.duration) {
      current.offset = 0;
    }
    startSources(current.offset);
    current.playing = true;
    tick();
    setPlayIcon(true);
    updateMediaSession();
  }

  function pausePlayback() {
    if (!current || !current.playing) {
      return;
    }
    // ctx.currentTime stands still while the system has paused the
    // context, so this is also the right position after an interruption.
    current.offset = position();
    current.playing = false;
    stopSources();
    cancelAnimationFrame(current.raf);
    if (audioEl) {
      audioEl.pause();
    }
    setPlayIcon(false);
    updateMediaSession();
  }

  function togglePlay() {
    if (!current || !current.buffers) {
      return;
    }
    if (current.playing) {
      pausePlayback();
    }
    else {
      play();
    }
  }

  function seek(pos) {
    if (current.playing) {
      startSources(pos);
    }
    else {
      current.offset = pos;
    }
    updateProgress(pos);
    updateMediaSession();
  }

  function buildTrackRows(tracks) {
    const wrap = dialog.querySelector('.gob-player__tracks');
    wrap.innerHTML = '';
    return tracks.map((track, i) => {
      const row = document.createElement('div');
      row.className = 'gob-player__track';
      row.innerHTML =
        '<span class="gob-player__name"></span>' +
        '<input class="gob-player__volume" type="range" min="0" max="120" value="80" aria-label="Volym">' +
        '<span class="gob-player__buttons">' +
        '  <button type="button" class="gob-player__mute">Tyst</button>' +
        '  <button type="button" class="gob-player__solo">Solo</button>' +
        '</span>';
      row.querySelector('.gob-player__name').textContent = track.label;
      row.querySelector('.gob-player__volume').setAttribute('aria-label', 'Volym för ' + track.label);
      row.querySelector('.gob-player__volume').addEventListener('input', (e) => {
        current.tracks[i].volume = e.target.value / 100;
        applyGains();
      });
      row.querySelector('.gob-player__mute').addEventListener('click', () => {
        current.tracks[i].muted = !current.tracks[i].muted;
        applyGains();
      });
      row.querySelector('.gob-player__solo').addEventListener('click', () => {
        current.solo[i] = !current.solo[i];
        applyGains();
      });
      wrap.appendChild(row);
      return row;
    });
  }

  async function open(title, tracks) {
    if (!dialog) {
      buildDialog();
    }
    ensureContext();

    stopAll();
    dialog.querySelector('.gob-player__title').textContent = title;
    const status = dialog.querySelector('.gob-player__status');
    const master = dialog.querySelector('.gob-player__master');
    status.hidden = false;
    master.hidden = true;
    status.textContent = 'Hämtar ljudfiler ...';
    dialog.querySelector('.gob-player__tracks').innerHTML = '';
    dialog.showModal();

    const state = {
      tracks: tracks.map((t) => ({ label: t.label, muted: false, volume: 0.8 })),
      solo: tracks.map(() => false),
      buffers: null,
      sources: null,
      offset: 0,
      playing: false,
      duration: 0,
    };
    current = state;

    try {
      let loaded = 0;
      const buffers = await Promise.all(tracks.map(async (track) => {
        const response = await fetch(track.url, { credentials: 'same-origin' });
        if (!response.ok) {
          throw new Error(track.label);
        }
        const data = await response.arrayBuffer();
        loaded++;
        if (current === state) {
          status.textContent = 'Hämtar ljudfiler ... ' + loaded + ' av ' + tracks.length;
        }
        return ctx.decodeAudioData(data);
      }));

      // The dialog may have been closed or reopened while loading.
      if (current !== state) {
        return;
      }

      state.buffers = buffers;
      state.duration = Math.max(...buffers.map((b) => b.duration));
      state.gains = buffers.map(() => {
        const gain = ctx.createGain();
        gain.connect(outputNode());
        return gain;
      });
      state.rows = buildTrackRows(state.tracks);
      applyGains();

      if ('mediaSession' in navigator && window.MediaMetadata) {
        navigator.mediaSession.metadata = new MediaMetadata({ title: title, artist: 'Gott och Blandat' });
      }

      status.hidden = true;
      master.hidden = false;
      updateProgress(0);
      setPlayIcon(false);
    }
    catch (error) {
      if (current === state) {
        status.textContent = 'Ljudfilen för ' + error.message + ' kunde inte hämtas. Prova igen senare.';
      }
    }
  }

  Drupal.behaviors.gobPlayer = {
    attach(context) {
      once('gob-player', '.note-row__listen', context).forEach((button) => {
        button.addEventListener('click', () => {
          open(button.dataset.playerTitle, JSON.parse(button.dataset.playerTracks));
        });
      });
    },
  };
})(Drupal, once);
