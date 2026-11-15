import {
  GameState, SkillType, TIERS, TIER_COUNT, tierOf, radiusOf,
  SKILL_COST, SKILL_NAME, SWAP_UNLOCK_SPENT,
  DANGER_SECONDS, ENERGY_MAX, ENERGY_RING_SLOTS
} from './Config';
import { Body, UiButton, SkillButton } from './Model';
import { Layout } from './Layout';
import { GameEngine } from './GameEngine';
import { Assets } from './Assets';
import { FontKit } from './FontKit';
import { image } from '@kit.ImageKit';

const INK: string = '#222222';       // 原版 logo 深灰近黑
const PAPER: string = '#FFFDF6';     // 米白（兽脸 / 浅底）
const TEAL: string = '#2E9E7E';      // 青绿（技力进行中的填充）
const GOLD: string = '#FFAA00';      // 原版金黄强调（满格/连击/选中/高分）
const TAN: string = '#A48052';       // 原版暖棕描边
const TAN_D: string = '#6A4D27';     // 深棕文字
const TAN_L: string = '#C9B08A';     // 浅棕描边

/**
 * 全 Canvas 绘制：ArkUI 只在界面切换时重排，逐帧不触发组件重建。
 * 所有视觉元素均来自原版素材（Assets 加载的 PixelMap），
 * 个别资源缺失时自动回退到极简自绘，保证游戏仍可运行。
 */
export class Renderer {
  private assets: Assets | null = null;

  setAssets(a: Assets): void {
    this.assets = a;
  }

  /** 贴图原始宽高比：绘制时按比例内缩再居中，避免被目标框硬拉伸（标题页装饰图被压扁就是这个原因） */
  private drawFit(ctx: CanvasRenderingContext2D, name: string, x: number, y: number,
    w: number, h: number, alpha: number): boolean {
    let ar: number = 0;
    if (name === 'ui_title_deco') {
      ar = 76 / 64;
    } else if (name === 'ui_character') {
      ar = 187 / 224;
    }
    if (ar > 0) {
      if (w / h > ar) {
        const nh: number = w / ar;
        y += (h - nh) / 2;
        h = nh;
      } else {
        const nw: number = h * ar;
        x += (w - nw) / 2;
        w = nw;
      }
    }
    return Assets.draw(ctx, this.pm(name), x, y, w, h, alpha);
  }

  private pm(name: string): image.PixelMap | null {
    return this.assets === null ? null : this.assets.get(name);
  }

  draw(ctx: CanvasRenderingContext2D, engine: GameEngine, now: number): void {
    const L: Layout = engine.layout;
    // 画布像素尺寸与布局单位可能不一致（ArkUI 的 vp 与 Canvas 内部像素不同）：
    // 统一按画布像素缩放，否则背景/HUD 只能覆盖画布的一部分、其余露出底色
    const sx: number = ctx.width > 0 ? ctx.width / L.w : 1;
    const sy: number = ctx.height > 0 ? ctx.height / L.h : 1;
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    ctx.save();
    ctx.scale(sx, sy);
    ctx.globalAlpha = 1;
    ctx.setLineDash([]);
    // 圆形表盘：内容一律裁到内切圆内，不会出现直角背景溢出圆弧
    if (L.round) {
      ctx.beginPath();
      ctx.arc(L.w / 2, L.h / 2, L.s * 0.5, 0, Math.PI * 2);
      ctx.clip();
    }
    // 与原版一致的薄荷绿底色（上浅下深）
    const bgG = ctx.createLinearGradient(0, 0, 0, L.h);
    bgG.addColorStop(0, '#9AD8C5');
    bgG.addColorStop(1, '#6FBFA8');
    ctx.fillStyle = bgG;
    ctx.fillRect(0, 0, L.w, L.h);

    ctx.save();
    if (engine.shakeAmp > 0.15) {
      // 三组互不整除的频率叠加 + 每次摇晃换一组相位：轨迹不重复、方向随机，
      // 而固定 sin/cos 会走成一条圆形轨迹，看起来像整屏在绕圈
      const sa: number = engine.shakeAmp;
      const t: number = now * 0.001;
      const sd: number = engine.shakeSeed;
      let ox: number = (Math.sin(t * 37.1 + sd) * 0.5 + Math.sin(t * 61.7 + sd * 1.7) * 0.3 +
        Math.sin(t * 23.9 + sd * 0.6) * 0.2) * sa * 1.5;
      let oy: number = (Math.cos(t * 41.3 + sd * 1.3) * 0.5 + Math.cos(t * 67.9 + sd * 0.8) * 0.3 +
        Math.cos(t * 27.7 + sd * 2.1) * 0.2) * sa;
      const mag: number = Math.sqrt(ox * ox + oy * oy);
      if (mag > sa) {
        ox = ox / mag * sa;
        oy = oy / mag * sa;
      }
      ctx.translate(ox, oy);
    }
    this.drawAmbient(ctx, L);
    this.drawWell(ctx, L, engine);
    this.drawEndmin(ctx, L);
    this.drawAim(ctx, L, engine);
    this.drawBodies(ctx, L, engine);
    this.drawEffects(ctx, L, engine);
    ctx.restore();

    const st: GameState = engine.state;
    const fullOverlay: boolean = st === GameState.MENU || st === GameState.PAUSED ||
      st === GameState.CODEX || st === GameState.RESULT;
    if (!fullOverlay) {
      this.drawHud(ctx, L, engine);
    }
    this.drawOverlay(ctx, L, engine);

    if (engine.flashTimer > 0) {
      ctx.save();
      ctx.globalAlpha = Math.min(0.85, engine.flashTimer * 1.1);
      if (!Assets.draw(ctx, this.pm('bg_max_synth'), L.w / 2 - L.s * 0.36, L.s * 0.30,
        L.s * 0.72, L.s * 0.44, 1)) {
        ctx.fillStyle = '#FFE9A8';
        ctx.fillRect(0, 0, L.w, L.h);
      }
      ctx.restore();
    }
  }

  // ---------------------------------------------------------------- 背景 / 容器
  private drawAmbient(ctx: CanvasRenderingContext2D, L: Layout): void {
    ctx.save();
    ctx.globalAlpha = 0.16;
    Assets.draw(ctx, this.pm('bg_menu'), 0, 0, L.w, L.h, 1);
    ctx.restore();
    if (L.round) {
      ctx.save();
      ctx.globalAlpha = 0.6;
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = L.s * 0.008;
      ctx.beginPath();
      ctx.arc(L.w / 2, L.h / 2, L.s * 0.475, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
  }

  private wellPath(ctx: CanvasRenderingContext2D, L: Layout): void {
    const r: number = L.s * (L.round ? 0.075 : 0.045);
    const x0: number = L.wellL;
    const y0: number = L.wellT;
    const x1: number = L.wellR;
    const y1: number = L.wellB;
    ctx.beginPath();
    ctx.moveTo(x0 + r, y0);
    ctx.lineTo(x1 - r, y0);
    ctx.quadraticCurveTo(x1, y0, x1, y0 + r);
    ctx.lineTo(x1, y1 - r);
    ctx.quadraticCurveTo(x1, y1, x1 - r, y1);
    ctx.lineTo(x0 + r, y1);
    ctx.quadraticCurveTo(x0, y1, x0, y1 - r);
    ctx.lineTo(x0, y0 + r);
    ctx.quadraticCurveTo(x0, y0, x0 + r, y0);
    ctx.closePath();
  }

  private drawWell(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    ctx.save();
    this.wellPath(ctx, L);
    ctx.clip();
    // 原版游戏主视觉（青绿纹理）
    if (!Assets.draw(ctx, this.pm('bg_game'), L.wellL, L.wellT,
      L.wellR - L.wellL, L.wellB - L.wellT, 1)) {
      ctx.fillStyle = '#EAF8EF';
      ctx.fillRect(L.wellL, L.wellT, L.wellR - L.wellL, L.wellB - L.wellT);
    }
    ctx.save();
    ctx.globalAlpha = 0.10;
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(L.wellL, L.wellT, L.wellR - L.wellL, L.wellB - L.wellT);
    ctx.restore();

    const heat: number = engine.dangerTimer / DANGER_SECONDS;
    if (heat > 0) {
      Assets.draw(ctx, this.pm('ui_danger_overlay'), L.wellL, L.wellT - L.s * 0.02,
        L.wellR - L.wellL, L.s * 0.10, 0.35 + heat * 0.5);
    }
    // 原版红线：红绿相间的矩形段
    if (!Assets.draw(ctx, this.pm('ui_danger_line'), L.wellL, L.dangerY - L.s * 0.004,
      L.wellR - L.wellL, L.s * 0.009, heat > 0 ? 1 : 0.9)) {
      const seg: number = L.s * 0.014;
      const y0: number = L.dangerY - L.s * 0.0055;
      const n: number = Math.floor((L.wellR - L.wellL) / seg);
      for (let dk: number = 0; dk < n; dk++) {
        ctx.fillStyle = (dk % 2 === 0)
          ? (heat > 0 ? '#FF5C6C' : '#E05060')
          : (heat > 0 ? '#3FA46A' : '#3E9A66');
        ctx.fillRect(L.wellL + dk * seg, y0, seg, L.s * 0.011);
      }
    }
    ctx.restore();

    ctx.save();
    this.wellPath(ctx, L);
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = L.s * 0.010;
    ctx.stroke();
    ctx.strokeStyle = TAN;
    ctx.lineWidth = L.s * 0.004;
    ctx.stroke();
    ctx.restore();
  }

  /** 原版：两个管理员坐在容器口，从袋子里丢出山团团 */
  private drawEndmin(ctx: CanvasRenderingContext2D, L: Layout): void {
    const dw: number = L.unit * 1.04;
    const dh: number = dw * (490 / 1104);
    Assets.draw(ctx, this.pm('endmins'), L.cx - dw / 2, L.wellT - dh * 0.90, dw, dh, 1);
  }

  // ---------------------------------------------------------------- 团团
  private drawBodies(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    // 漂浮/摇晃期间球会冲出容器顶：不再裁剪到容器，让越界部分可见（画布边缘自然会截掉飞出屏幕的部分）
    if (engine.windTimer > 0 || engine.shakeTimer > 0) {
      for (let j: number = 0; j < engine.bodies.length; j++) {
        this.drawBlob(ctx, engine.bodies[j]);
      }
      return;
    }
    ctx.save();
    this.wellPath(ctx, L);
    ctx.clip();
    for (let i: number = 0; i < engine.bodies.length; i++) {
      this.drawBlob(ctx, engine.bodies[i]);
    }
    ctx.restore();
    // 刚从管理员丢出、尚在容器口上方的球不裁剪，体现「从袋子丢出」
    for (let k: number = 0; k < engine.bodies.length; k++) {
      const bk: Body = engine.bodies[k];
      if (bk.y - bk.r < L.wellT) {
        this.drawBlob(ctx, bk);
      }
    }
  }

  private drawBlob(ctx: CanvasRenderingContext2D, b: Body): void {
    const t = tierOf(b.level);
    const pop: number = 0.72 + 0.28 * b.pop;
    const sx: number = pop * (1 + b.squash * 0.10);
    const sy: number = pop * (1 - b.squash * 0.10);
    const r: number = b.r * 1.06;   // 贴图含耳朵/角，略放大让圆脸接近物理半径
    ctx.save();
    ctx.translate(b.x, b.y);
    ctx.scale(sx, sy);
    const pm = this.assets === null ? null : this.assets.tier(b.level);
    if (!Assets.draw(ctx, pm, -r, -r, r * 2, r * 2, 1)) {
      ctx.beginPath();
      ctx.arc(0, 0, b.r, 0, Math.PI * 2);
      ctx.fillStyle = t.main;
      ctx.fill();
      ctx.lineWidth = Math.max(1, b.r * 0.085);
      ctx.strokeStyle = t.dark;
      ctx.stroke();
      // 原版「山团团」兽脸：白脸 + 深色眼睛 + 小嘴
      const fy: number = -b.r * 0.06;
      const fr: number = b.r * 0.60;
      ctx.beginPath();
      ctx.arc(0, fy, fr, 0, Math.PI * 2);
      ctx.fillStyle = PAPER;
      ctx.fill();
      ctx.lineWidth = Math.max(1, b.r * 0.045);
      ctx.strokeStyle = t.dark;
      ctx.stroke();
      const er: number = b.r * 0.10;
      const ex: number = b.r * 0.22;
      const ey: number = fy - b.r * 0.04;
      ctx.fillStyle = t.dark;
      ctx.beginPath();
      ctx.arc(-ex, ey, er, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(ex, ey, er, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = t.dark;
      ctx.lineWidth = Math.max(1, b.r * 0.05);
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.arc(0, fy + b.r * 0.16, b.r * 0.11, 0, Math.PI);
      ctx.stroke();
    }
    if (b.mark) {
      ctx.strokeStyle = GOLD;
      ctx.lineWidth = Math.max(1.5, b.r * 0.10);
      ctx.setLineDash([b.r * 0.22, b.r * 0.16]);
      ctx.beginPath();
      ctx.arc(0, 0, b.r * 1.16, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.restore();
  }

  private drawMiniBlob(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
    level: number, alpha: number): void {
    const t = tierOf(level);
    const pm = this.assets === null ? null : this.assets.icon(level);
    if (Assets.draw(ctx, pm, x - r, y - r, r * 2, r * 2, alpha)) {
      return;
    }
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = t.main;
    ctx.fill();
    ctx.lineWidth = Math.max(1, r * 0.10);
    ctx.strokeStyle = t.dark;
    ctx.stroke();
    if (r > 0.02) {
      const fy: number = y - r * 0.06;
      const fr: number = r * 0.58;
      ctx.beginPath();
      ctx.arc(x, fy, fr, 0, Math.PI * 2);
      ctx.fillStyle = PAPER;
      ctx.fill();
      ctx.lineWidth = Math.max(0.5, r * 0.06);
      ctx.strokeStyle = t.dark;
      ctx.stroke();
      ctx.fillStyle = t.dark;
      const er: number = r * 0.11;
      const ex: number = r * 0.24;
      const ey: number = fy - r * 0.04;
      ctx.beginPath();
      ctx.arc(x - ex, ey, er, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(x + ex, ey, er, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  // ---------------------------------------------------------------- 瞄准 / 特效
  private drawAim(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    if (engine.state !== GameState.PLAYING || engine.dropTimer > 0.14) {
      return;
    }
    const r: number = radiusOf(engine.nextLevel, L.unit);
    ctx.save();
    this.wellPath(ctx, L);
    ctx.clip();
    ctx.setLineDash([L.s * 0.014, L.s * 0.020]);
    ctx.globalAlpha = 0.55;
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = L.s * 0.006;
    ctx.beginPath();
    ctx.moveTo(engine.aimX, L.spawnY + r);
    ctx.lineTo(engine.aimX, L.wellB);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
    this.drawMiniBlob(ctx, engine.aimX, L.spawnY, r, engine.nextLevel, 0.72);
  }

  private drawEffects(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    for (let i: number = 0; i < engine.particles.length; i++) {
      const p = engine.particles[i];
      ctx.save();
      ctx.globalAlpha = Math.max(0, p.life / p.maxLife);
      ctx.fillStyle = p.color;
      this.circle(ctx, p.x, p.y, p.r);
      ctx.restore();
    }
    // 合成时撒原版金色星星
    const star = this.pm('ui_star');
    if (star !== null) {
      const s: number = L.s * 0.035;
      for (let i: number = 0; i < engine.particles.length; i += 5) {
        const p = engine.particles[i];
        Assets.draw(ctx, star, p.x - s / 2, p.y - s / 2, s, s,
          Math.max(0, p.life / p.maxLife) * 0.85);
      }
    }
    for (let i: number = 0; i < engine.floatTexts.length; i++) {
      const f = engine.floatTexts[i];
      ctx.save();
      ctx.globalAlpha = Math.min(1, f.life / f.maxLife * 1.6);
      this.text(ctx, f.text, f.x, f.y, f.size, GOLD, true);
      ctx.restore();
    }
  }

  // ---------------------------------------------------------------- HUD
  private drawHud(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    const S: number = L.s;
    const showToast: boolean = engine.toastTimer > 0;

    // 顶部原版分数面板
    Assets.draw(ctx, this.pm('ui_score'), L.scoreX - S * 0.22,
      L.scoreY - S * 0.056, S * 0.44, S * 0.105, 0.94);
    this.text(ctx, String(engine.score), L.scoreX, L.scoreY - S * 0.008,
      L.scoreFont * 0.88, INK, true);
    if (!showToast) {
      this.text(ctx, '最高 ' + engine.highScore + ' · 合成 ' + engine.merges,
        L.highX, L.highY, L.highFont, '#4A5A52', false);
    }
    if (engine.combo > 1 && engine.comboTimer > 0) {
      this.text(ctx, '连击 x' + engine.combo, L.scoreX, L.highY + S * 0.044,
        S * 0.033, GOLD, true);
    }

    // 下一个：原版点阵圆底 + 原版小图
    Assets.draw(ctx, this.pm('ui_next'), L.nextX - L.nextR, L.nextY - L.nextR,
      L.nextR * 2, L.nextR * 2, 0.95);
    this.drawMiniBlob(ctx, L.nextX, L.nextY, L.nextR * 0.68, engine.nextLevel, 1);
    this.text(ctx, '下一个', L.nextX, L.nextY + L.nextR + S * 0.022,
      S * 0.032, '#4A5A52', false);

    // 技力条：原版白底 + 青绿/金色分段
    const ex: number = L.energyX - L.energyW / 2;
    const gap: number = S * 0.008;
    const segW: number = (L.energyW - gap * 2) / 3;
    Assets.draw(ctx, this.pm('ui_energy'), ex - S * 0.012,
      L.energyY - L.energyH / 2 - S * 0.006,
      L.energyW + S * 0.024, L.energyH + S * 0.012, 0.92);
    for (let i: number = 0; i < 3; i++) {
      const x: number = ex + i * (segW + gap);
      this.roundRect(ctx, x, L.energyY - L.energyH / 2, segW, L.energyH, L.energyH / 2);
      ctx.fillStyle = '#F0D9BC';
      ctx.fill();
      ctx.strokeStyle = TAN_L;
      ctx.lineWidth = S * 0.003;
      ctx.stroke();
      // 用平滑显示值绘制：整条连续增长，不再按整格跳动
      const fill: number = Math.max(0, Math.min(1, engine.energyView - i));
      if (fill > 0) {
        ctx.save();
        ctx.beginPath();
        ctx.rect(x, L.energyY - L.energyH / 2, segW * fill, L.energyH);
        ctx.clip();
        this.roundRect(ctx, x, L.energyY - L.energyH / 2, segW, L.energyH, L.energyH / 2);
        // 充满整条才变金：此前第三格一有进度就是金色，看起来像「黄着没满」
        ctx.fillStyle = engine.energy >= ENERGY_MAX ? GOLD : TEAL;
        ctx.fill();
        ctx.restore();
      }
    }
    // 技力条底部扇贝波浪边（对齐原版 skillbar-bg）
    ctx.save();
    ctx.fillStyle = '#F0D9BC';
    ctx.beginPath();
    const scallop: number = 6;
    for (let sc: number = 0; sc < scallop; sc++) {
      const scx: number = ex + (sc + 0.5) * (L.energyW / scallop);
      ctx.moveTo(scx, L.energyY + L.energyH / 2);
      ctx.arc(scx, L.energyY + L.energyH / 2, segW * 0.22, 0, Math.PI);
    }
    ctx.fill();
    ctx.restore();
    let label: string = '技力 ' + engine.energy + '/' + ENERGY_MAX.toFixed(0);
    if (engine.energyRing > 0.5) {
      label += '  ' + Math.floor(engine.energyRing) + '/' + ENERGY_RING_SLOTS.toFixed(0);
    }
    this.text(ctx, label, L.energyX, L.energyY - L.energyH - S * 0.021, S * 0.031, '#4A5A52', false);

    // 四个原版战技圆形图标
    for (let i: number = 0; i < L.skillButtons.length; i++) {
      this.drawSkill(ctx, L, engine, L.skillButtons[i]);
    }

    // 红线倒计时：原版数字贴纸
    if (engine.dangerTimer > 0) {
      const left: number = Math.max(1, Math.ceil(DANGER_SECONDS - engine.dangerTimer));
      const cs: number = S * 0.17;
      Assets.draw(ctx, this.assets === null ? null : this.assets.count(left),
        L.w / 2 - cs / 2, L.dangerY + S * 0.02, cs, cs, 0.95);
    }

    // 提示条（顶部信息带，不遮挡容器）
    if (showToast) {
      ctx.save();
      ctx.globalAlpha = Math.min(1, engine.toastTimer * 2);
      const tw: number = L.round ? S * 0.44 : S * 0.62;
      const th: number = S * 0.050;
      const tx: number = L.round ? L.highX : L.scoreX;
      this.roundRect(ctx, tx - tw / 2, L.highY - th / 2, tw, th, th / 2);
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      ctx.strokeStyle = TAN_L;
      ctx.lineWidth = S * 0.004;
      ctx.stroke();
      this.text(ctx, engine.toast, tx, L.highY, S * 0.030, INK, false);
      ctx.restore();
    }

    if (engine.state === GameState.TARGET_CLEAR || engine.state === GameState.TARGET_SWAP) {
      const msg: string = engine.state === GameState.TARGET_CLEAR
        ? '舍弃：点选一个团团' : '互换：依次点选两个团团';
      this.text(ctx, msg, L.w / 2, L.wellT + S * 0.075, S * 0.043, TAN_D, true);
    }
  }

  private drawSkill(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine,
    b: SkillButton): void {
    const ready: boolean = engine.isSkillReady(b.index);
    const locked: boolean = b.index === SkillType.SWAP && !engine.swapUnlocked;
    const chosen: boolean = engine.selectedSkill === b.index;
    const r: number = b.r * 1.16;
    ctx.save();
    ctx.beginPath();
    ctx.arc(b.x, b.y, r, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
    ctx.strokeStyle = chosen ? GOLD : TAN_L;
    ctx.lineWidth = L.s * (chosen ? 0.010 : 0.005);
    ctx.stroke();
    ctx.restore();
    const pm = this.assets === null ? null : this.assets.skill(b.index);
    if (!Assets.draw(ctx, pm, b.x - r, b.y - r, r * 2, r * 2,
      locked ? 0.38 : (ready ? 1 : 0.62))) {
      // 原版技能图标素材（白兽脸+彩色圆底）；素材缺失时才回退到程序符号
      const al: number = locked ? 0.38 : (ready ? 1 : 0.62);
      this.drawSkillGlyph(ctx, b.x, b.y - b.r * 0.10, b.r * 0.50, b.index, INK, al);
    }
    if (chosen) {
      ctx.strokeStyle = GOLD;
      ctx.lineWidth = L.s * 0.010;
      ctx.beginPath();
      ctx.arc(b.x, b.y, r * 1.04, 0, Math.PI * 2);
      ctx.stroke();
    }
    let label: string;
    if (locked) {
      label = SKILL_NAME[b.index] + ' ' + Math.floor(Math.min(engine.spentTotal, SWAP_UNLOCK_SPENT)) + '/6';
    } else if (b.index === SkillType.SWAP) {
      // 互换蓄能完成后不扣技力，直接可用
      label = SKILL_NAME[b.index] + ' 就绪';
    } else {
      label = SKILL_NAME[b.index] + ' ' + SKILL_COST[b.index] + '力';
    }
    // 名称/消耗内嵌在圆形图标底部，避免小表盘下被屏幕边缘裁切
    const bw: number = r * 2;
    const bh: number = r * 0.52;
    const by: number = b.y + r - bh;
    ctx.save();
    ctx.globalAlpha = 0.86;
    this.roundRect(ctx, b.x - bw / 2, by, bw, bh, bh / 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
    ctx.restore();
    this.text(ctx, label, b.x, by + bh / 2, b.r * 0.42,
      ready ? INK : '#93A79C', false);
  }

  /** 技能图标符号：舍弃 × / 漂浮上升气流 / 摇晃水平波浪 / 互换双向箭头 */
  private drawSkillGlyph(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
    k: number, color: string, alpha: number): void {
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = r * 0.18;
    ctx.lineCap = 'round';
    if (k === 0) {
      ctx.beginPath();
      ctx.moveTo(x - r * 0.5, y - r * 0.5);
      ctx.lineTo(x + r * 0.5, y + r * 0.5);
      ctx.moveTo(x + r * 0.5, y - r * 0.5);
      ctx.lineTo(x - r * 0.5, y + r * 0.5);
      ctx.stroke();
    } else if (k === 1) {
      ctx.beginPath();
      for (let i: number = 0; i < 3; i++) {
        const yy: number = y + r * 0.42 - i * r * 0.42;
        ctx.moveTo(x - r * 0.58, yy);
        ctx.quadraticCurveTo(x - r * 0.29, yy - r * 0.36, x, yy);
        ctx.quadraticCurveTo(x + r * 0.29, yy + r * 0.36, x + r * 0.58, yy);
      }
      ctx.stroke();
    } else if (k === 2) {
      ctx.beginPath();
      for (let j: number = 0; j < 3; j++) {
        const yy2: number = y - r * 0.42 + j * r * 0.42;
        ctx.moveTo(x - r * 0.58, yy2);
        ctx.quadraticCurveTo(x, yy2 - r * 0.36, x + r * 0.58, yy2);
      }
      ctx.stroke();
    } else {
      const ar: number = r * 0.34;
      ctx.beginPath();
      ctx.moveTo(x - r * 0.68, y);
      ctx.lineTo(x + r * 0.68, y);
      ctx.moveTo(x + r * 0.68, y);
      ctx.lineTo(x + r * 0.32, y - ar);
      ctx.moveTo(x + r * 0.68, y);
      ctx.lineTo(x + r * 0.32, y + ar);
      ctx.moveTo(x - r * 0.68, y);
      ctx.lineTo(x - r * 0.32, y - ar);
      ctx.moveTo(x - r * 0.68, y);
      ctx.lineTo(x - r * 0.32, y + ar);
      ctx.stroke();
    }
    ctx.restore();
  }

  // ---------------------------------------------------------------- 覆盖层
  private drawOverlay(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    const s: GameState = engine.state;
    if (s === GameState.PLAYING) {
      return;
    }
    const S: number = L.s;
    const light: boolean = s === GameState.TARGET_CLEAR || s === GameState.TARGET_SWAP;
    if (!light) {
      ctx.save();
      if (s === GameState.MENU) {
        Assets.draw(ctx, this.pm('bg_menu'), 0, 0, L.w, L.h, 1);
        ctx.globalAlpha = 0.12;
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, L.w, L.h);
      } else {
        Assets.draw(ctx, this.pm('bg_panel'), L.s * 0.04, L.s * 0.04,
          L.w - L.s * 0.08, L.h - L.s * 0.08, 1);

      }
      ctx.restore();
    }

    switch (s) {
      case GameState.MENU:
        this.drawFit(ctx, 'ui_title_deco', L.w / 2 - S * 0.07,
          S * 0.100, S * 0.14, S * 0.118, 0.95);
        this.text(ctx, '融合！山团团！', L.w / 2, S * 0.265, S * 0.100, INK, true);
        this.text(ctx, 'HarmonyOS 智能手表版', L.w / 2, S * 0.335,
          S * 0.040, '#4A5A52', false);
        this.drawFit(ctx, 'ui_character', L.w / 2 - S * 0.225,
          S * 0.375, S * 0.075, S * 0.075, 0.95);
        this.text(ctx, '最高分 ' + engine.highScore, L.w / 2, S * 0.435,
          S * 0.052, INK, true);
        this.text(ctx, '点按投放 / 拖动瞄准 / 表冠微调', L.w / 2, S * 0.485,
          S * 0.035, '#4A5A52', false);
        break;
      case GameState.PAUSED:
        this.text(ctx, '已暂停', L.w / 2, S * 0.28, S * 0.095, INK, true);
        this.text(ctx, '得分 ' + engine.score, L.w / 2, S * 0.355,
          S * 0.045, '#4A5A52', false);
        break;
      case GameState.CODEX:
        this.drawCodex(ctx, L, engine);
        break;
      case GameState.RESULT:
        Assets.draw(ctx, this.pm('ui_trophy'), L.w / 2 - S * 0.05,
          S * 0.135, S * 0.10, S * 0.10, 1);
        this.text(ctx, '本局结束', L.w / 2, S * 0.265, S * 0.080, INK, true);
        this.text(ctx, String(engine.score), L.w / 2, S * 0.375, S * 0.145, GOLD, true);
        this.text(ctx, '最高 ' + engine.highScore + ' · 合成 ' + engine.merges +
          ' 次 · 战技 ' + engine.skillUses + ' 次', L.w / 2, S * 0.475,
          S * 0.036, '#4A5A52', false);
        this.text(ctx, '最高融合：' + tierOf(engine.maxTier).name, L.w / 2, S * 0.535,
          S * 0.040, GOLD, false);
        break;
      default:
        break;
    }

    for (let i: number = 0; i < L.buttons.length; i++) {
      this.drawButton(ctx, L, L.buttons[i], !light && i === 0);
    }
  }

  private drawCodex(ctx: CanvasRenderingContext2D, L: Layout, engine: GameEngine): void {
    const S: number = L.s;
    this.text(ctx, '融合图鉴', L.w / 2, S * 0.135, S * 0.075, INK, true);
    this.text(ctx, '相同山团团相撞 → 更大的山团团', L.w / 2, S * 0.205,
      S * 0.033, '#4A5A52', false);
    for (let i: number = 0; i < TIER_COUNT; i++) {
      const cell: number[] = L.codexCell(i);
      const unlocked: boolean = (i + 1) <= engine.save.maxTier;
      if (unlocked) {
        this.drawMiniBlob(ctx, cell[0], cell[1], cell[2], i + 1, 1);
      } else {
        ctx.save();
        ctx.globalAlpha = 0.22;
        ctx.fillStyle = '#C9D6D1';
        this.circle(ctx, cell[0], cell[1], cell[2] * 0.9);
        ctx.restore();
      }
      this.text(ctx, unlocked ? TIERS[i].name : '???', cell[0], cell[1] + cell[2] + S * 0.030,
        S * 0.028, unlocked ? INK : '#A8B5AE', false);
    }
  }

  private drawButton(ctx: CanvasRenderingContext2D, L: Layout, b: UiButton,
    primary: boolean): void {
    this.roundRect(ctx, b.x - b.w / 2, b.y - b.h / 2, b.w, b.h, b.h / 2);
    ctx.fillStyle = primary ? GOLD : '#FFFFFF';
    ctx.fill();
    ctx.lineWidth = L.s * 0.005;
    ctx.strokeStyle = primary ? GOLD : TAN_L;
    ctx.stroke();
    this.text(ctx, b.label, b.x, b.y, Math.min(b.h * 0.44, L.s * 0.048),
      primary ? TAN_D : '#3D4A43', true);
  }

  // ---------------------------------------------------------------- 绘图工具
  private circle(ctx: CanvasRenderingContext2D, x: number, y: number, r: number): void {
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }

  private roundRect(ctx: CanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number): void {
    const rr: number = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
    ctx.lineTo(x + rr, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
    ctx.lineTo(x, y + rr);
    ctx.quadraticCurveTo(x, y, x + rr, y);
    ctx.closePath();
  }

  private text(ctx: CanvasRenderingContext2D, str: string, x: number, y: number,
    size: number, color: string, bold: boolean): void {
    ctx.save();
    ctx.font = (bold ? 'bold ' : '') + size.toFixed(1) + 'px ' + FontKit.css();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = color;
    // 金黄/米白文字加深棕描边，保证浅色薄荷底上可读
    if (color === GOLD || color === PAPER) {
      ctx.lineWidth = Math.max(1, size * 0.12);
      ctx.strokeStyle = TAN_D;
      ctx.strokeText(str, x, y);
    }
    ctx.fillText(str, x, y);
    ctx.restore();
  }
}
