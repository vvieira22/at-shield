// A.T. Shield comfort page — petals + leaves + fireflies
document.documentElement.dataset.shield = "1";

const QUOTES = [
  "Link the fire. O resto pode esperar.",
  "Bonfire lit. Descanse, ashen one.",
  "Você morreu. Levante. De novo.",
  "Don't you dare go hollow.",
  "A pressa é o verdadeiro boss.",
  "Praise the Sun — e respira fundo.",
  "Token of friendship: ficar aqui um pouco.",
  "Não fuja. Fique. Só por agora.",
  "The fate of destruction is also the joy of rebirth.",
  "Você não está sozinho nesse cockpit.",
  "Get in the robot — mas primeiro, respire.",
  "I mustn't run away. Nem do silêncio.",
  "Um momento sem AT Field também conta.",
  "Achievement unlocked: escolheu ficar.",
  "git commit -m \"pause\"",
  "Loading… character development.",
  "Press start to continue — later.",
  "Não há sidequest urgente demais.",
  "Mana regenerando. Aguarde.",
  "Save point alcançado.",
  "O feed não tem main quest.",
  "Ctrl+Z na ansiedade. Enter no agora.",
  "It's dangerous to go alone — fica.",
];

// soft garden palette — sakura / autumn / dusk
const PETAL_COLORS = [
  ["#ffd6e7", "#f8a0c0"],
  ["#ffe8f0", "#e891c0"],
  ["#fff0f5", "#d45b8c"],
  ["#e8d5ff", "#b39ddb"],
  ["#ffe4c4", "#e0a060"],
  ["#fff4c4", "#e8c05a"],
  ["#e8f5c8", "#9ccc65"],
  ["#ffccbc", "#ff8a65"],
  ["#fce4ec", "#f48fb1"],
  ["#efebe9", "#bcaaa4"],
];

const LEAF_COLORS = [
  ["#c6e06a", "#7cb342"],
  ["#aed581", "#558b2f"],
  ["#ffcc80", "#ef6c00"],
  ["#ffab91", "#e64a19"],
  ["#ffe082", "#f9a825"],
  ["#d7ccc8", "#8d6e63"],
  ["#bcaaa4", "#6d4c41"],
  ["#ff8a65", "#d84315"],
  ["#9ccc65", "#33691e"],
  ["#ffd54f", "#ff8f00"],
];

function pick(n) {
  const bag = QUOTES.slice();
  for (let i = bag.length - 1; i > 0; i--) {
    const j = (Math.random() * (i + 1)) | 0;
    [bag[i], bag[j]] = [bag[j], bag[i]];
  }
  return bag.slice(0, n);
}

function renderCredits() {
  const track = document.querySelector(".credits-track");
  if (!track) return;
  const lines = pick(5);
  track.replaceChildren(
    ...lines.flatMap((text, i) => {
      const p = document.createElement("p");
      p.textContent = text;
      if (i === lines.length - 1) return [p];
      const sep = document.createElement("hr");
      sep.className = "sep";
      return [p, sep];
    }),
  );
}

function startFx() {
  const canvas = document.getElementById("fx");
  if (!canvas || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const ctx = canvas.getContext("2d");
  let w = 0;
  let h = 0;
  let wind = 0;
  const flakes = [];
  const flies = [];
  const motes = [];
  const mouse = { x: -9999, y: -9999, active: false };

  function resize() {
    w = canvas.width = window.innerWidth;
    h = canvas.height = window.innerHeight;
  }

  function spawnFlake(seeded) {
    const isLeaf = Math.random() < 0.48;
    const pair = (isLeaf ? LEAF_COLORS : PETAL_COLORS)[
      (Math.random() * (isLeaf ? LEAF_COLORS : PETAL_COLORS).length) | 0
    ];
    flakes.push({
      kind: isLeaf ? "leaf" : "petal",
      x: seeded ? Math.random() * w : Math.random() * (w + 80) - 40,
      y: seeded ? Math.random() * h : -20 - Math.random() * 60,
      vx: (Math.random() - 0.5) * 0.15,
      vy: 0.1 + Math.random() * (isLeaf ? 0.2 : 0.18),
      rot: Math.random() * Math.PI * 2,
      spin: (Math.random() - 0.5) * (isLeaf ? 0.028 : 0.02),
      sway: Math.random() * Math.PI * 2,
      swaySpeed: 0.012 + Math.random() * 0.018,
      swayAmp: 0.4 + Math.random() * 0.7,
      w: isLeaf ? 6 + Math.random() * 9 : 5 + Math.random() * 8,
      h: isLeaf ? 9 + Math.random() * 12 : 7 + Math.random() * 10,
      alpha: 0.55 + Math.random() * 0.35,
      c1: pair[0],
      c2: pair[1],
      z: 0.7 + Math.random() * 0.5,
    });
  }

  function spawnFly() {
    flies.push({
      x: Math.random() * w,
      y: h * 0.15 + Math.random() * h * 0.6,
      vx: (Math.random() - 0.5) * 0.18,
      vy: (Math.random() - 0.5) * 0.14,
      size: 1.6 + Math.random() * 2.2,
      phase: Math.random() * Math.PI * 2,
      // slow gentle blink
      speed: 0.0006 + Math.random() * 0.0008,
      life: Math.random(),
      hue: Math.random() < 0.6 ? "255, 230, 140" : "210, 255, 170",
    });
  }

  function spawnMote() {
    motes.push({
      x: Math.random() * w,
      y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.08,
      vy: -0.02 - Math.random() * 0.06,
      size: 0.6 + Math.random() * 1.4,
      alpha: 0.12 + Math.random() * 0.2,
      sway: Math.random() * Math.PI * 2,
    });
  }

  function drawPetal(p) {
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.rot);
    ctx.scale(p.z, p.z);
    ctx.globalAlpha = p.alpha;

    const g = ctx.createRadialGradient(0, -p.h * 0.2, 0, 0, 0, p.h);
    g.addColorStop(0, p.c1);
    g.addColorStop(1, p.c2);
    ctx.fillStyle = g;

    ctx.beginPath();
    ctx.ellipse(0, 0, p.w * 0.55, p.h * 0.55, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.globalAlpha = p.alpha * 0.55;
    ctx.beginPath();
    ctx.ellipse(-p.w * 0.15, p.h * 0.05, p.w * 0.35, p.h * 0.4, -0.35, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }

  function drawLeaf(p) {
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.rot);
    ctx.scale(p.z, p.z);
    ctx.globalAlpha = p.alpha;

    const g = ctx.createLinearGradient(0, -p.h, 0, p.h);
    g.addColorStop(0, p.c1);
    g.addColorStop(1, p.c2);
    ctx.fillStyle = g;

    ctx.beginPath();
    ctx.moveTo(0, -p.h * 0.55);
    ctx.quadraticCurveTo(p.w * 0.7, -p.h * 0.1, p.w * 0.35, p.h * 0.45);
    ctx.quadraticCurveTo(0, p.h * 0.2, -p.w * 0.35, p.h * 0.45);
    ctx.quadraticCurveTo(-p.w * 0.7, -p.h * 0.1, 0, -p.h * 0.55);
    ctx.fill();

    ctx.globalAlpha = p.alpha * 0.4;
    ctx.strokeStyle = p.c2;
    ctx.lineWidth = 0.7;
    ctx.beginPath();
    ctx.moveTo(0, -p.h * 0.4);
    ctx.lineTo(0, p.h * 0.3);
    ctx.stroke();

    ctx.restore();
  }

  function frame(t) {
    ctx.clearRect(0, 0, w, h);

    // soft global breeze
    wind += (Math.sin(t * 0.00025) * 0.35 - wind) * 0.02;

    while (flakes.length < 58) spawnFlake(false);
    while (flies.length < 28) spawnFly();
    while (motes.length < 30) spawnMote();

    // pollen / dust — behind everything
    for (let i = motes.length - 1; i >= 0; i--) {
      const m = motes[i];
      m.sway += 0.01;
      m.x += m.vx + Math.sin(m.sway) * 0.15 + wind * 0.15;
      m.y += m.vy;
      if (m.y < -10 || m.x < -20 || m.x > w + 20) {
        motes[i] = motes[motes.length - 1];
        motes.pop();
        continue;
      }
      ctx.globalAlpha = m.alpha;
      ctx.fillStyle = "#fff8e7";
      ctx.beginPath();
      ctx.arc(m.x, m.y, m.size, 0, Math.PI * 2);
      ctx.fill();
    }

    // petals + leaves
    for (let i = flakes.length - 1; i >= 0; i--) {
      const p = flakes[i];
      p.sway += p.swaySpeed;

      if (mouse.active) {
        const dx = p.x - mouse.x;
        const dy = p.y - mouse.y;
        const d2 = dx * dx + dy * dy;
        if (d2 < 160 * 160 && d2 > 4) {
          const d = Math.sqrt(d2);
          const f = (1 - d / 160) * 0.4;
          p.vx += (dx / d) * f;
          p.vy += (dy / d) * f * 0.5;
        }
      }

      p.vx *= 0.99;
      p.vy = p.vy * 0.995 + 0.001;
      p.x += (p.vx + Math.sin(p.sway) * p.swayAmp * 0.35 + wind) * p.z;
      p.y += p.vy * p.z;
      p.rot += p.spin + p.vx * 0.008;

      if (p.y > h + 40 || p.x < -60 || p.x > w + 60) {
        flakes[i] = flakes[flakes.length - 1];
        flakes.pop();
        continue;
      }
      if (p.kind === "leaf") drawLeaf(p);
      else drawPetal(p);
    }

    // fireflies — additive glow
    ctx.globalCompositeOperation = "lighter";
    for (const f of flies) {
      f.life += f.speed;
      // ease blink: soft rise, soft fall, short dark gap
      const wave = Math.sin(f.life * Math.PI * 2 + f.phase);
      const alpha = Math.pow(Math.max(0, wave), 1.4) * 0.95;
      f.x += f.vx + Math.sin(t * 0.001 + f.phase) * 0.12 + wind * 0.08;
      f.y += f.vy + Math.cos(t * 0.0008 + f.phase) * 0.1;
      if (f.x < 0 || f.x > w) f.vx *= -1;
      if (f.y < h * 0.1 || f.y > h * 0.85) f.vy *= -1;

      if (alpha < 0.03) continue;

      const r = f.size * (0.9 + alpha * 0.7);
      ctx.fillStyle = `rgba(${f.hue}, ${alpha})`;
      ctx.beginPath();
      ctx.arc(f.x, f.y, r, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = `rgba(${f.hue}, ${alpha * 0.35})`;
      ctx.beginPath();
      ctx.arc(f.x, f.y, r * 3.2, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = `rgba(${f.hue}, ${alpha * 0.12})`;
      ctx.beginPath();
      ctx.arc(f.x, f.y, r * 6, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;

    requestAnimationFrame(frame);
  }

  window.addEventListener("mousemove", (e) => {
    mouse.x = e.clientX;
    mouse.y = e.clientY;
    mouse.active = true;
  });
  window.addEventListener("mouseleave", () => {
    mouse.active = false;
  });

  resize();
  window.addEventListener("resize", resize);
  for (let i = 0; i < 52; i++) spawnFlake(true);
  for (let i = 0; i < 26; i++) spawnFly();
  for (let i = 0; i < 25; i++) spawnMote();
  requestAnimationFrame(frame);
}

renderCredits();
startFx();
