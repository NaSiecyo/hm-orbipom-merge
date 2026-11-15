import {
  GameState, SkillType, TIER_COUNT, tierOf, radiusOf, clamp,
  FIXED_DT, MAX_STEPS_PER_FRAME, MAX_BODIES, SOLVER_ITERATIONS, SPAWN_MAX_TIER,
  DANGER_SECONDS, DROP_COOLDOWN, COMBO_WINDOW, COMBO_MAX, SKILL_COST,
  SWAP_UNLOCK_SPENT, WIND_SECONDS, ENERGY_MAX,
  ENERGY_RING_SLOTS, ENERGY_RING_IDLE, ENERGY_RING_DECAY,
  GRAVITY_RATIO, RESTITUTION, WALL_RESTITUTION, TANGENT_FRICTION,
  AIR_DRAG, MAX_SPEED_RATIO,
  WIND_FILL, WIND_HOLD, WIND_DRAIN, WIND_LEVEL_RATIO, WIND_BUOY_MUL, WIND_RHO_SCALE,
  WIND_LIGHT_MUL, WIND_HEAVY_MUL, WIND_DRAG, WIND_MAX_RISE, WIND_DRIFT, WIND_DRIFT_FREQ,
  WIND_GRACE,
  SHAKE_SECONDS, SHAKE_AMP_RATIO, SHAKE_APEX_RATIO, SHAKE_RISE_RATIO, SHAKE_SPREAD, SHAKE_TILT, SHAKE_GRACE,
  DANGER_BOX_RATIO, DANGER_CALM_RATIO, SHAKE_BOX_RATIO, SHAKE_JITTER, SHAKE_VARY, SHAKE_BOOST, WIND_DENSITY,
  POS_CORRECTION, BOUNCE_MIN_RATIO, REST_VEL_RATIO, CONTACT_EPS_RATIO, SOLVER_SLOP_RATIO,
  TIE_RATIO, BALL_FRICTION
} from './Config';
import { Body, Particle, FloatText } from './Model';
import { Layout, ScreenAdapter } from './Layout';
import { SaveStore } from './SaveStore';

const SPAWN_WEIGHTS: number[] = [0.31, 0.26, 0.20, 0.14, 0.09];

/**
 * 纯 ArkTS 实现的 2D 圆形刚体世界 + 原版「融合！山团团！」玩法状态机。
 * 不依赖任何第三方物理库：固定步长、位置松弛求解、同级接触即融合，
 * 单个表盘上最多 42 个刚体，O(n^2) 碰撞在手表端开销可忽略。
 */
export class GameEngine {
  layout: Layout = new Layout();
  save: SaveStore = new SaveStore();
  state: GameState = GameState.MENU;
  codexFrom: GameState = GameState.MENU;

  bodies: Body[] = [];
  particles: Particle[] = [];
  floatTexts: FloatText[] = [];

  score: number = 0;
  highScore: number = 0;
  merges: number = 0;
  skillUses: number = 0;
  maxTier: number = 1;
  /** 已攒满的技力整格数（0~3），整格不会被时间衰减。 */
  energy: number = 0;
  /** 当前这一格的进度环（0~ENERGY_RING_SLOTS），只有它会随空闲回落。 */
  energyRing: number = 0;
  /** 技力条的显示值（0~3，浮点）：平滑追赶真实值，避免进度一跳一跳。 */
  energyView: number = 0;
  /** 距上次合成经过的秒数，用于判断何时开始掉环。 */
  idleSeconds: number = 0;
  spentTotal: number = 0;
  combo: number = 0;
  comboTimer: number = 0;
  nextLevel: number = 1;
  aimX: number = 0;
  dropTimer: number = 0;
  dangerTimer: number = 0;
  windTimer: number = 0;
  /** 漂浮是否生效：生效时取消容器顶盖，让球可以冲出容器甚至飞出屏幕。 */
  windOn: boolean = false;
  /** 虚拟水面进度：0 = 容器底，1 = 目标水位（漂浮三阶段由它驱动）。 */
  windSurface: number = 0;
  /** 漂浮结束后的红线宽限期（秒）：球还在下落途中，暂不判红线。 */
  windGrace: number = 0;
  shakeTimer: number = 0;
  shakeAmp: number = 0;
  /** 摇晃结束后的红线宽限期（秒）：球还在空中/下落途中，暂不判红线。 */
  shakeGrace: number = 0;
  /** 每次摇晃的抖动相位种子：换一个种子就换一条轨迹，避免每次抖动完全一样。 */
  shakeSeed: number = 0;
  flashTimer: number = 0;
  swapUnlocked: boolean = false;
  selectedSkill: number = -1;
  targetFirst: number = -1;
  toast: string = '';
  toastTimer: number = 0;
  lastGain: number = 0;
  lastGainTimer: number = 0;

  private rngSeed: number = 20261112;
  private nextId: number = 1;
  private lastNow: number = 0;
  private accumulator: number = 0;
  private lastDangerBeep: number = 0;
  /** 逐刚体的「下方有支撑」标记，预分配复用，物理步内不做内存分配。 */
  private support: boolean[] = [];

  /** Index 注入：表盘形状切换后重新计算布局。 */
  relayoutCallback: () => void = () => {};
  /** Index 注入：原版音效播放钩子。 */
  onSound: (key: string) => void = () => {};

  private sfx(key: string): void {
    this.onSound(key);
  }

  // ---------------------------------------------------------------- 生命周期
  initSave(high: number, tier: number): void {
    this.highScore = high;
    this.maxTier = clamp(tier, 1, TIER_COUNT);
  }

  applyLayout(w: number, h: number): void {
    let round: boolean;
    if (this.save.shapeMode === 1) {
      round = true;
    } else if (this.save.shapeMode === 2) {
      round = false;
    } else {
      round = ScreenAdapter.detectRound(w, h);
    }
    this.layout.recompute(w, h, round);
    this.rehomeBodies();
    this.alignAim();
    this.refreshButtons();
  }

  shapeLabel(): string {
    if (this.save.shapeMode === 0) {
      return this.layout.round ? '布局 · 自动(圆)' : '布局 · 自动(方)';
    }
    if (this.save.shapeMode === 1) {
      return '布局 · 圆形表盘';
    }
    return '布局 · 方形表盘';
  }

  cycleShape(): void {
    this.save.shapeMode = (this.save.shapeMode + 1) % 3;
    this.save.save();
    this.relayoutCallback();
  }

  refreshButtons(): void {
    this.layout.setButtons(this.state, this.shapeLabel());
  }

  setState(s: GameState): void {
    this.state = s;
    this.refreshButtons();
  }

  startGame(): void {
    this.bodies = [];
    this.particles = [];
    this.floatTexts = [];
    this.score = 0;
    this.merges = 0;
    this.skillUses = 0;
    this.energy = 0;
    this.energyRing = 0;
    this.energyView = 0;
    this.idleSeconds = 0;
    this.spentTotal = 0;
    this.combo = 0;
    this.comboTimer = 0;
    this.dangerTimer = 0;
    this.lastDangerBeep = 0;
    this.windTimer = 0;
    this.windGrace = 0;
    this.windSurface = 0;
    this.shakeTimer = 0;
    this.shakeGrace = 0;
    this.shakeSeed = 0;
    this.flashTimer = 0;
    this.swapUnlocked = false;
    this.selectedSkill = -1;
    this.targetFirst = -1;
    this.dropTimer = 0;
    this.lastNow = 0;
    this.accumulator = 0;
    this.nextId = 1;
    this.nextLevel = this.randomSpawn();
    this.aimX = (this.layout.wellL + this.layout.wellR) / 2;
    this.setState(GameState.PLAYING);
    this.showToast('轻点投放 · 拖动瞄准');
  }

  backToMenu(): void {
    this.setState(GameState.MENU);
  }

  pause(): void {
    if (this.state === GameState.TARGET_CLEAR || this.state === GameState.TARGET_SWAP) {
      this.cancelTargeting();
    }
    if (this.state === GameState.PLAYING) {
      this.setState(GameState.PAUSED);
    }
  }

  resume(): void {
    if (this.state === GameState.PAUSED) {
      this.setState(GameState.PLAYING);
    }
  }

  openCodex(): void {
    this.codexFrom = this.state;
    this.setState(GameState.CODEX);
  }

  closeCodex(): void {
    this.setState(this.codexFrom);
  }

  handleButton(id: number): void {
    this.sfx('click');
    switch (this.state) {
      case GameState.MENU:
        if (id === 1) {
          this.startGame();
        } else if (id === 2) {
          this.openCodex();
        } else if (id === 3) {
          this.cycleShape();
        }
        break;
      case GameState.PAUSED:
        if (id === 1) {
          this.resume();
        } else if (id === 2) {
          this.startGame();
        } else if (id === 3) {
          this.backToMenu();
        }
        break;
      case GameState.CODEX:
        if (id === 1) {
          this.closeCodex();
        }
        break;
      case GameState.RESULT:
        if (id === 1) {
          this.startGame();
        } else if (id === 2) {
          this.backToMenu();
        }
        break;
      case GameState.TARGET_CLEAR:
      case GameState.TARGET_SWAP:
        if (id === 1) {
          this.cancelTargeting();
        }
        break;
      default:
        break;
    }
  }

  /** 侧键 / 返回手势：优先关闭覆盖层，其次暂停。 */
  onBack(): void {
    if (this.state === GameState.CODEX) {
      this.closeCodex();
    } else if (this.state === GameState.TARGET_CLEAR || this.state === GameState.TARGET_SWAP) {
      this.cancelTargeting();
    } else if (this.state === GameState.PLAYING) {
      this.pause();
    } else if (this.state === GameState.PAUSED) {
      this.resume();
    } else if (this.state === GameState.RESULT) {
      this.backToMenu();
    }
  }

  // ---------------------------------------------------------------- 投放 / 瞄准
  private random(): number {
    this.rngSeed = (this.rngSeed * 1664525 + 1013904223) >>> 0;
    return this.rngSeed / 4294967296;
  }

  private randomSpawn(): number {
    const t: number = this.random();
    let acc: number = 0;
    for (let i: number = 0; i < SPAWN_MAX_TIER; i++) {
      acc += SPAWN_WEIGHTS[i];
      if (t <= acc) {
        return i + 1;
      }
    }
    return 1;
  }

  alignAim(): void {
    const r: number = radiusOf(this.nextLevel, this.layout.unit);
    const range: number[] = this.layout.aimRange(r);
    this.aimX = clamp(this.aimX, range[0], range[1]);
  }

  setAim(x: number): void {
    const r: number = radiusOf(this.nextLevel, this.layout.unit);
    const range: number[] = this.layout.aimRange(r);
    this.aimX = clamp(x, range[0], range[1]);
  }

  nudgeAim(delta: number): void {
    this.setAim(this.aimX + delta);
  }

  drop(): void {
    if (this.state !== GameState.PLAYING || this.dropTimer > 0) {
      return;
    }
    if (this.bodies.length >= MAX_BODIES) {
      this.showToast('空间不足 · 试试舍弃');
      return;
    }
    const b: Body = new Body();
    b.id = this.nextId++;
    b.level = this.nextLevel;
    b.r = radiusOf(b.level, this.layout.unit);
    // 同点连投时加极小横向抖动（±2% unit），避免完美共线叠成一根竖塔
    b.x = clamp(this.aimX + (this.random() - 0.5) * this.layout.unit * 0.04,
      this.layout.wellL + b.r, this.layout.wellR - b.r);
    // 从管理员袋子丢出：初始在容器口上方，带向下的抛投初速度
    b.y = this.layout.spawnY - this.layout.unit * 0.30;
    b.vx = (this.random() - 0.5) * this.layout.unit * 0.10;
    b.vy = this.layout.unit * 0.55;
    b.born = Date.now();
    b.pop = 0;
    // 漂浮中投放的新球也要有独立漂移相位，否则会跟别的球踩着同一节拍平移
    b.windPhase = this.random() * Math.PI * 2;
    this.bodies.push(b);
    this.spawnPuff(b.x, b.y, tierOf(b.level).light, 5);
    this.sfx('drop');
    this.nextLevel = this.randomSpawn();
    this.dropTimer = DROP_COOLDOWN;
    this.alignAim();
  }

  // ---------------------------------------------------------------- 战技
  isSkillReady(index: number): boolean {
    // 互换是充能制：累计消耗满 SWAP_UNLOCK_SPENT 点技力即可直接触发，不再额外扣技力
    if (index === SkillType.SWAP) {
      return this.swapUnlocked;
    }
    return this.energy >= SKILL_COST[index];
  }

  useSkill(index: number): void {
    if (this.state !== GameState.PLAYING) {
      return;
    }
    if (index < 0 || index > 3) {
      return;
    }
    if (index === SkillType.SWAP && !this.swapUnlocked) {
      this.showToast('累计消耗 6 技力解锁互换');
      return;
    }
    if (this.energy < SKILL_COST[index]) {
      this.showToast('技力不足');
      return;
    }
    this.selectedSkill = index;
    if (index === SkillType.CLEAR) {
      if (this.bodies.length === 0) {
        this.selectedSkill = -1;
        this.showToast('场上没有团团');
        return;
      }
      this.targetFirst = -1;
      this.setState(GameState.TARGET_CLEAR);
      this.sfx('select');
      this.showToast('点选要舍弃的团团');
    } else if (index === SkillType.SWAP) {
      this.targetFirst = -1;
      this.setState(GameState.TARGET_SWAP);
      this.showToast('依次点选两个团团');
    } else if (index === SkillType.WIND) {
      this.windTimer = WIND_SECONDS;
      this.windGrace = 0;
      this.startWind();
      this.paySkill(index);
      this.sfx('wind');
      this.showToast('协议·漂浮 已启动');
    } else {
      // 整堆同速上抛：统一速度下球与球之间没有相对速度，不会互相挤压缩放能量，
      // 堆叠保持原样整体弹起再整体落下，看起来才是「一起被掀起」而不是各飞各的
      const L: Layout = this.layout;
      const g: number = L.unit * GRAVITY_RATIO;
      const cx: number = L.cx;
      const apexY: number = L.wellT + (L.wellB - L.wellT) * SHAKE_APEX_RATIO;
      // 用「最上方球的球顶」而不是球心：否则大球会先撞到容器口，被顶盖压住白掉速度
      let topEdge: number = L.wellB;
      for (let q: number = 0; q < this.bodies.length; q++) {
        const edge: number = this.bodies[q].y - this.bodies[q].r;
        if (edge < topEdge) {
          topEdge = edge;
        }
      }
      let lift: number = topEdge - apexY;
      if (lift < (L.wellB - L.wellT) * SHAKE_RISE_RATIO) {
        lift = (L.wellB - L.wellT) * SHAKE_RISE_RATIO;
      }
      let vUp: number = Math.sqrt(2 * g * lift) * SHAKE_BOOST;
      const vCap: number = L.unit * MAX_SPEED_RATIO;
      if (vUp > vCap) {
        vUp = vCap;
      }
      for (let i: number = 0; i < this.bodies.length; i++) {
        const b: Body = this.bodies[i];
        // 方向 = 辐射扇形（越靠外越斜）+ 每球独立随机偏转；力度也带随机但幅度一致，
        // 这样每次按下去方向都不重样，又不会出现某颗特别猛 / 特别蔫
        let nx: number = (b.x - cx) / (L.unit * 0.52);
        if (nx > 1) {
          nx = 1;
        } else if (nx < -1) {
          nx = -1;
        }
        // 每球左右方向随机（整堆左右都有人去），基础倾角让「左右动量 ≈ 垂直动量」，
        // 再叠加「越靠外越斜」的位置外扩与随机偏转；力度随机但幅度一致
        const dir: number = this.random() < 0.5 ? -1 : 1;
        const tilt: number = dir * (SHAKE_TILT + Math.atan(Math.abs(nx) * SHAKE_SPREAD) * 0.5) +
          (this.random() - 0.5) * 2 * SHAKE_JITTER;
        const sp: number = vUp * (1 - SHAKE_VARY * 0.5 + this.random() * SHAKE_VARY);
        b.vy = -sp * Math.cos(tilt);
        b.vx += sp * Math.sin(tilt);
      }
      this.shakeTimer = SHAKE_SECONDS;
      this.shakeGrace = SHAKE_GRACE;
      this.shakeSeed = this.random() * 100;
      this.shakeAmp = L.s * SHAKE_AMP_RATIO;
      this.paySkill(index);
      this.sfx('shake');
      this.showToast('摇晃！');
    }
  }

  // ---------------------------------------------------------------- 漂浮（水位 + 浮力）
  /**
   * 释放漂浮：水位从 0 开始，给每颗球一个独立的漂移相位。
   * 真正的抬升由 step() 里的浮力负责，这里只做初始化。
   */
  private startWind(): void {
    this.windSurface = 0;
    for (let i: number = 0; i < this.bodies.length; i++) {
      this.bodies[i].windPhase = this.random() * Math.PI * 2;
    }
  }

  /** 当前虚拟水面高度（vp）：未漂浮时等于容器底。 */
  windSurfaceY(): number {
    const L: Layout = this.layout;
    const h: number = L.wellB - L.wellT;
    const top: number = L.wellT + h * WIND_LEVEL_RATIO;
    return L.wellB - (L.wellB - top) * this.windSurface;
  }

  /** 漂浮三阶段：灌入 → 维持 → 抽回（对齐原版 fill/hold/drain）。 */
  private advanceWindSurface(dt: number): void {
    const elapsed: number = WIND_SECONDS - this.windTimer;
    if (elapsed < WIND_FILL) {
      this.windSurface = elapsed / WIND_FILL;
    } else if (elapsed < WIND_FILL + WIND_HOLD) {
      this.windSurface = 1;
    } else if (elapsed < WIND_SECONDS) {
      this.windSurface = Math.max(0, 1 - (elapsed - WIND_FILL - WIND_HOLD) / WIND_DRAIN);
    } else {
      this.windSurface = 0;
    }
  }

  private clearWindState(): void {
    this.windSurface = 0;
    for (let i: number = 0; i < this.bodies.length; i++) {
      this.bodies[i].windPhase = 0;
    }
  }

  private paySkill(index: number): void {
    this.skillUses++;
    this.selectedSkill = -1;
    if (index === SkillType.SWAP) {
      // 用掉一次互换：充能清零，需要重新累计 6 点技力
      this.spentTotal = 0;
      this.swapUnlocked = false;
      this.showToast('互换已用尽 · 重新蓄能');
      return;
    }
    const cost: number = SKILL_COST[index];
    this.energy = Math.max(0, this.energy - cost);
    this.spentTotal += cost;
    if (!this.swapUnlocked && this.spentTotal >= SWAP_UNLOCK_SPENT) {
      this.swapUnlocked = true;
      this.showToast('命定互换 就绪！');
    }
  }

  cancelTargeting(): void {
    this.targetFirst = -1;
    this.selectedSkill = -1;
    this.clearMarks();
    this.setState(GameState.PLAYING);
  }

  private clearMarks(): void {
    for (let i: number = 0; i < this.bodies.length; i++) {
      this.bodies[i].mark = false;
    }
  }

  /** 战技选点：返回是否命中了团团。 */
  tapBody(x: number, y: number): boolean {
    if (this.state !== GameState.TARGET_CLEAR && this.state !== GameState.TARGET_SWAP) {
      return false;
    }
    const b: Body | null = this.pickBody(x, y);
    if (b === null) {
      return false;
    }
    if (this.state === GameState.TARGET_CLEAR) {
      this.spawnPuff(b.x, b.y, tierOf(b.level).light, 14);
      const idx: number = this.bodies.indexOf(b);
      if (idx >= 0) {
        this.bodies.splice(idx, 1);
      }
      this.paySkill(SkillType.CLEAR);
      this.sfx('clear');
      this.setState(GameState.PLAYING);
      return true;
    }
    if (this.targetFirst < 0) {
      this.targetFirst = b.id;
      b.mark = true;
      this.showToast('再选一个团团');
      return true;
    }
    const other: Body | null = this.findById(this.targetFirst);
    if (other === null) {
      // 首次选中的团团已在此期间被融合掉：清掉标记，让玩家重新选第一个
      this.clearMarks();
      this.targetFirst = -1;
      b.mark = true;
      this.targetFirst = b.id;
      this.showToast('第一个目标已消失 · 重新选择');
      return true;
    }
    if (other === b) {
      return true;
    }
    const tx: number = b.x;
    const ty: number = b.y;
    const tvx: number = b.vx;
    const tvy: number = b.vy;
    b.x = other.x;
    b.y = other.y;
    b.vx = other.vx;
    b.vy = other.vy;
    other.x = tx;
    other.y = ty;
    other.vx = tvx;
    other.vy = tvy;
    this.spawnPuff(b.x, b.y, '#FFE38A', 10);
    this.spawnPuff(other.x, other.y, '#FFE38A', 10);
    this.clearMarks();
    this.targetFirst = -1;
    this.paySkill(SkillType.SWAP);
    this.sfx('swap');
    this.setState(GameState.PLAYING);
    return true;
  }

  private findById(id: number): Body | null {
    for (let i: number = 0; i < this.bodies.length; i++) {
      if (this.bodies[i].id === id) {
        return this.bodies[i];
      }
    }
    return null;
  }

  private pickBody(x: number, y: number): Body | null {
    let best: Body | null = null;
    let bestD: number = 1e9;
    for (let i: number = 0; i < this.bodies.length; i++) {
      const b: Body = this.bodies[i];
      const dx: number = x - b.x;
      const dy: number = y - b.y;
      const d: number = Math.sqrt(dx * dx + dy * dy);
      if (d <= b.r * 1.12 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- 物理步进
  private active(): boolean {
    return this.state === GameState.PLAYING || this.state === GameState.TARGET_CLEAR ||
      this.state === GameState.TARGET_SWAP;
  }

  step(dt: number): void {
    this.updateEffects(dt);
    if (!this.active()) {
      return;
    }

    this.dropTimer = Math.max(0, this.dropTimer - dt);
    const windWasActive: boolean = this.windTimer > 0;
    this.windTimer = Math.max(0, this.windTimer - dt);
    const windActive: boolean = this.windTimer > 0;
    this.windOn = windActive;
    if (windActive) {
      // 水位在灌入/维持/抽回三段之间推进，浮力由当前水位决定
      this.advanceWindSurface(dt);
    } else if (windWasActive) {
      // 水面已退到容器底：本步起按正常重力下落，并进入红线宽限期
      this.windGrace = WIND_GRACE;
      this.clearWindState();
    } else if (this.windGrace > 0) {
      this.windGrace = Math.max(0, this.windGrace - dt);
    }
    this.shakeTimer = Math.max(0, this.shakeTimer - dt);
    if (this.shakeGrace > 0) {
      this.shakeGrace = Math.max(0, this.shakeGrace - dt);
    }
    // 抖动幅度按「每秒」衰减：固定步长 120Hz 下若按步乘 0.9 会在 0.1s 内衰减殆尽
    this.shakeAmp *= Math.max(0, 1 - 1.4 * dt);   // 1.4/s 衰减：前 0.3 秒不会就看不见
    if (this.shakeTimer <= 0) {
      this.shakeAmp = 0;
    }
    if (this.comboTimer > 0) {
      this.comboTimer -= dt;
      if (this.comboTimer <= 0) {
        this.combo = 0;
      }
    }
    // 技力：整格不衰减，只有未满那一格的进度环在空闲 2 秒后按每秒 1 环回落
    this.idleSeconds += dt;
    if (this.energyRing > 0 && this.idleSeconds > ENERGY_RING_IDLE) {
      this.energyRing = Math.max(0, this.energyRing - ENERGY_RING_DECAY * dt);
    }
    // 显示值平滑追赶「整格 + 当前格进度」，进度条就不会一格一格地跳
    const target: number = clamp(this.energy + this.energyRing / ENERGY_RING_SLOTS, 0, ENERGY_MAX);
    this.energyView += (target - this.energyView) * Math.min(1, dt * 6);

    const L: Layout = this.layout;
    const gravity: number = L.unit * GRAVITY_RATIO;
    const drag: number = Math.max(0, 1 - AIR_DRAG * dt);
    const maxSpeed: number = L.unit * MAX_SPEED_RATIO;
    const riseCap: number = L.unit * WIND_MAX_RISE;
    const fluidDrag: number = Math.max(0, 1 - WIND_DRAG * dt);
    const surfaceY: number = this.windSurfaceY();
    const driftAcc: number = L.unit * WIND_DRIFT;
    const n: number = this.bodies.length;
    this.ensureScratch(n);
    for (let i: number = 0; i < n; i++) {
      this.support[i] = false;
    }

    for (let i: number = 0; i < n; i++) {
      const b: Body = this.bodies[i];
      b.age += dt;
      if (b.pop < 1) {
        b.pop = Math.min(1, b.pop + dt * 7);
      }
      b.squash *= Math.max(0, 1 - dt * 5);
      if (windActive) {
        // 漂浮：重力照常作用，额外叠加「按浸没深度」的浮力（原版 buoyancyPerMass 的加速度版）。
        // 球越深浮力越大 → 被托出水面；浮到水面时浸没比例趋零，浮力≈重力，自然悬停。
        // 浸没深度：水面越靠上（y 越小），球被淹没得越多；球顶刚好在水面时为满浸没
        const depth: number = b.y - surfaceY + b.r;
        let sub: number = depth / (b.r * 2);
        if (sub < 0) {
          sub = 0;
        } else if (sub > 1) {
          sub = 1;
        }
        b.vy += gravity * dt;
        if (sub > 0) {
          // 密度权重：低阶「轻」，高阶「重」，重球浮力小、升得慢（原版 densityToWind / rhoScale）
          const dens: number = WIND_DENSITY[clamp(b.level - 1, 0, 10)];
          const w: number = dens / WIND_RHO_SCALE;
          let lift: number = gravity * WIND_BUOY_MUL * sub / w;
          if (w < 1) {
            lift *= WIND_LIGHT_MUL;
          } else if (w > 1.02) {
            lift *= WIND_HEAVY_MUL;
          }
          b.vy -= lift * dt;
        }
        // 流体阻力（原版 frictionAir）+ 横向漂移，把整堆揉散、位置重新洗牌
        b.vx *= fluidDrag;
        b.vy *= fluidDrag;
        b.vx += Math.sin(b.age * WIND_DRIFT_FREQ + b.windPhase) * driftAcc * dt;
        if (b.vy < -riseCap) {
          b.vy = -riseCap;
        }
      } else {
        b.vy += gravity * dt;
        b.vx *= drag;
        b.vy *= drag;
        const sp: number = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (sp > maxSpeed) {
          b.vx = b.vx / sp * maxSpeed;
          b.vy = b.vy / sp * maxSpeed;
        }
      }
      b.x += b.vx * dt;
      b.y += b.vy * dt;
    }

    // 位置松弛：速度冲量只在本步第一次迭代施加，之后只解重叠，避免恢复系数被反复叠加
    const slop: number = L.unit * SOLVER_SLOP_RATIO;
    for (let it: number = 0; it < SOLVER_ITERATIONS; it++) {
      const worst: number = this.solvePairs(it === 0);
      for (let i: number = 0; i < n; i++) {
        this.constrainPos(this.bodies[i]);
      }
      if (worst < slop) {
        break;
      }
    }

    // 墙面/地面的速度响应每步只做一次（此前在 3 次迭代里各做一次，符号被反复翻转）
    for (let i: number = 0; i < n; i++) {
      this.resolveWall(this.bodies[i], i);
    }
    // 近静止清零：让堆叠真正停下来；漂浮期间由速度伺服接管，不做清零
    if (!windActive) {
      this.settleRest(n);
    }

    this.resolveMerges();
    this.checkDanger(dt);
  }

  /** 支撑标记数组按需扩容（只在球数增长时分配，物理步内零分配）。 */
  private ensureScratch(n: number): void {
    while (this.support.length < n) {
      this.support.push(false);
    }
  }

  /**
   * 成对求解：位置修正每次都做，速度冲量只在本步第一次迭代做。
   * 返回本步最大重叠量（vp），供调用方判断是否可以提前结束迭代。
   */
  private solvePairs(applyImpulse: boolean): number {
    const n: number = this.bodies.length;
    const touchScale: number = 1.02;   // 刚好相切也算支撑
    const supportDy: number = 0.35;    // 对方球心低于本球 0.35*(r1+r2) 才算下方支撑
    const bounce: number = this.layout.unit * BOUNCE_MIN_RATIO;
    // 摇晃期间球与球的碰撞半径临时收窄：整堆被压缩时不互相顶死，也更容易被斜向甩开
    const box: number = this.shakeTimer > 0 ? SHAKE_BOX_RATIO : 1;
    let maxOverlap: number = 0;
    for (let i: number = 0; i < n; i++) {
      const a: Body = this.bodies[i];
      for (let j: number = i + 1; j < n; j++) {
        const b: Body = this.bodies[j];
        let dx: number = b.x - a.x;
        let dy: number = b.y - a.y;
        const minD: number = a.r + b.r;
        const hitD: number = minD * box;
        let d2: number = dx * dx + dy * dy;
        const touch2: number = minD * minD * touchScale;
        if (d2 < touch2) {
          const dyLimit: number = minD * supportDy;
          if (dy > dyLimit) {
            this.support[i] = true;
          } else if (dy < -dyLimit) {
            this.support[j] = true;
          }
        }
        if (d2 >= hitD * hitD) {
          continue;
        }
        // 同点连投会让两球横向偏移恒为 0，法线只剩竖直分量 → 挤压永远只能上下推、解不开。
        // 用 id 做确定性横向偏置打破这个退化（两端 id 镜像，行为一致）。
        const tie: number = hitD * TIE_RATIO;
        if (dx < tie && dx > -tie) {
          dx = a.id < b.id ? tie : -tie;
          d2 = dx * dx + dy * dy;
        }
        if (d2 < 0.0001) {
          dx = 0.01;
          dy = -0.01;
          d2 = 0.0002;
        }
        const d: number = Math.sqrt(d2);
        const nx: number = dx / d;
        const ny: number = dy / d;
        const ma: number = a.r * a.r;
        const mb: number = b.r * b.r;
        const total: number = ma + mb;
        const overlap: number = hitD - d;
        if (overlap > maxOverlap) {
          maxOverlap = overlap;
        }
        const ca: number = overlap * (mb / total) * POS_CORRECTION;
        const cb: number = overlap * (ma / total) * POS_CORRECTION;
        a.x -= nx * ca;
        a.y -= ny * ca;
        b.x += nx * cb;
        b.y += ny * cb;

        if (overlap > a.r * 0.06) {
          a.squash = Math.min(1, a.squash + 0.25);
          b.squash = Math.min(1, b.squash + 0.25);
        }
        if (!applyImpulse) {
          continue;
        }
        const rvx: number = b.vx - a.vx;
        const rvy: number = b.vy - a.vy;
        const vn: number = rvx * nx + rvy * ny;
        if (vn < 0) {
          // 低速接触按完全非弹性处理：否则每步都弹一点点，堆叠永远静不下来
          let rest: number = RESTITUTION;
          if (-vn < bounce) {
            rest = 0;
          }
          const imp: number = -(1 + rest) * vn / (1 / ma + 1 / mb);
          a.vx -= imp * nx / ma;
          a.vy -= imp * ny / ma;
          b.vx += imp * nx / mb;
          b.vy += imp * ny / mb;
          // 切向摩擦，避免团团在容器里无限滑行
          const tx: number = -ny;
          const ty: number = nx;
          const vt: number = rvx * tx + rvy * ty;
          const damp: number = vt * BALL_FRICTION;
          a.vx += damp * tx;
          a.vy += damp * ty;
          b.vx -= damp * tx;
          b.vy -= damp * ty;
        }
      }
    }
    return maxOverlap;
  }

  /** 只做位置回夹，不改速度（速度响应统一交给 resolveWall，每步一次）。 */
  private constrainPos(b: Body): void {
    const L: Layout = this.layout;
    if (b.x - b.r < L.wellL) {
      b.x = L.wellL + b.r;
    }
    if (b.x + b.r > L.wellR) {
      b.x = L.wellR - b.r;
    }
    if (b.y + b.r > L.wellB) {
      b.y = L.wellB - b.r;
    }
    if (this.windOn) {
      // 漂浮期间取消容器顶盖：允许球冲出容器顶，只保留远高于屏幕的兜底上限
      const cap: number = L.wellT - (L.wellB - L.wellT) * 0.9;
      if (b.y - b.r < cap) {
        b.y = cap + b.r;
      }
    } else if (this.shakeTimer > 0 || this.shakeGrace > 0) {
      // 摇晃期间（含宽限）也放开顶盖：整堆会明显冲出容器口再落回，只保留兜底上限
      const cap: number = L.wellT - (L.wellB - L.wellT) * 0.55;
      if (b.y - b.r < cap) {
        b.y = cap + b.r;
      }
    } else if (b.y - b.r < L.wellT) {
      // 平时顶部软墙与容器开口齐平：球被挤出容器后仍可见，避免「看不见的球」触发红线
      b.y = L.wellT + b.r;
    }
  }

  /**
   * 墙面/地面速度响应：每物理步只施加一次。
   * 低速接触直接吸收（置零），只有明显冲击才按恢复系数反弹，
   * 否则恢复系数会在每步被反复注入，堆叠会一直抖。
   */
  private resolveWall(b: Body, index: number): void {
    const L: Layout = this.layout;
    const eps: number = L.unit * CONTACT_EPS_RATIO;
    const bounce: number = L.unit * BOUNCE_MIN_RATIO;
    // 摇晃期间不吃墙面切向摩擦：否则贴墙的球每步被乘 1-FRIC，竖直速度 0.1 秒就被吃光，
    // 整堆只有中间的球飞得起来（这就是「不均匀」的根因）
    const wallFric: number = this.shakeTimer > 0 ? 0 : TANGENT_FRICTION;
    if (b.x - b.r <= L.wellL + eps) {
      if (b.vx < 0) {
        b.vx = -b.vx > bounce ? -b.vx * WALL_RESTITUTION : 0;
      }
      b.vy *= 1 - wallFric;
    }
    if (b.x + b.r >= L.wellR - eps) {
      if (b.vx > 0) {
        b.vx = b.vx > bounce ? -b.vx * WALL_RESTITUTION : 0;
      }
      b.vy *= 1 - wallFric;
    }
    if (b.y + b.r >= L.wellB - eps) {
      this.support[index] = true;
      if (b.vy > 0) {
        b.vy = b.vy > bounce ? -b.vy * WALL_RESTITUTION : 0;
      }
      b.vx *= 1 - wallFric;
    }
    if (!this.windOn && this.shakeTimer <= 0 && this.shakeGrace <= 0 && b.y - b.r <= L.wellT + eps) {
      if (b.vy < 0) {
        b.vy = -b.vy > bounce ? -b.vy * WALL_RESTITUTION : 0;
      }
    }
  }

  /** 近静止判定：有下方支撑且速度低于阈值时直接清零，让堆叠彻底停住。 */
  private settleRest(n: number): void {
    const rest: number = this.layout.unit * REST_VEL_RATIO;
    const rest2: number = rest * rest;
    for (let i: number = 0; i < n; i++) {
      if (!this.support[i]) {
        continue;
      }
      const b: Body = this.bodies[i];
      if (b.vx * b.vx + b.vy * b.vy < rest2) {
        b.vx = 0;
        b.vy = 0;
      }
    }
  }

  private resolveMerges(): void {
    const n: number = this.bodies.length;
    let merged: boolean = false;
    for (let i: number = 0; i < n; i++) {
      const a: Body = this.bodies[i];
      if (a.dead || a.age < 0.05) {
        continue;
      }
      for (let j: number = i + 1; j < n; j++) {
        const b: Body = this.bodies[j];
        if (b.dead || b.age < 0.05 || a.level !== b.level) {
          continue;
        }
        const dx: number = b.x - a.x;
        const dy: number = b.y - a.y;
        const minD: number = a.r + b.r;
        if (dx * dx + dy * dy > minD * minD * 1.02) {
          continue;
        }
        a.dead = true;
        b.dead = true;
        merged = true;
        this.doMerge(a, b);
        break;
      }
    }
    if (merged) {
      const alive: Body[] = [];
      for (let i: number = 0; i < this.bodies.length; i++) {
        if (!this.bodies[i].dead) {
          alive.push(this.bodies[i]);
        }
      }
      this.bodies = alive;
      // 新生成的团团位于两球中点，可能略微越界，立刻拉回容器
      for (let i: number = 0; i < this.bodies.length; i++) {
        this.constrainPos(this.bodies[i]);
      }
    }
  }

  private doMerge(a: Body, b: Body): void {
    const mx: number = (a.x + b.x) / 2;
    const my: number = (a.y + b.y) / 2;
    const newLevel: number = a.level + 1;
    const isUltimate: boolean = newLevel > TIER_COUNT;

    this.combo = Math.min(COMBO_MAX, this.combo + 1);
    this.comboTimer = COMBO_WINDOW;
    const mult: number = 1 + (this.combo - 1) * 0.25;
    const base: number = isUltimate ? 200 : tierOf(newLevel).score;
    const gain: number = Math.round(base * mult) + (isUltimate ? 500 : 0);
    this.score += gain;
    this.lastGain = gain;
    this.lastGainTimer = 1.0;
    this.merges++;
    this.idleSeconds = 0;
    if (this.energy < ENERGY_MAX) {
      this.energyRing += (0.09 + 0.03 * Math.min(newLevel, TIER_COUNT)) * ENERGY_RING_SLOTS;
      while (this.energyRing >= ENERGY_RING_SLOTS && this.energy < ENERGY_MAX) {
        this.energyRing -= ENERGY_RING_SLOTS;
        this.energy++;
      }
    }
    if (this.energy >= ENERGY_MAX) {
      this.energyRing = 0;
    }

    const shownTier: number = isUltimate ? TIER_COUNT : newLevel;
    if (shownTier > this.maxTier) {
      this.maxTier = shownTier;
    }
    if (shownTier > this.save.maxTier) {
      this.save.maxTier = shownTier;
      this.save.save();
    }

    const color: string = isUltimate ? '#FFE98A' : tierOf(newLevel).light;
    this.spawnPuff(mx, my, color, isUltimate ? 26 : 11);
    this.sfx(isUltimate ? 'golden' : 'merge');
    this.addFloat(mx, my - a.r * 0.4, '+' + gain, isUltimate ? '#FFE98A' : '#FFFFFF', this.layout.s * 0.055);

    if (!isUltimate) {
      const nb: Body = new Body();
      nb.id = this.nextId++;
      nb.level = newLevel;
      nb.r = radiusOf(newLevel, this.layout.unit);
      nb.x = mx;
      nb.y = my;
      nb.vx = (a.vx + b.vx) * 0.35;
      nb.vy = (a.vy + b.vy) * 0.35 - this.layout.unit * 0.20;
      nb.born = Date.now();
      nb.pop = 0;
      this.bodies.push(nb);
    } else {
      this.flashTimer = 0.75;
      this.showToast('终极融合 · 黄金管理员！');
    }
  }

  private checkDanger(dt: number): void {
    // 漂浮/摇晃期间与结束宽限期内暂停红线判定：技能必然把球抛过线，不能因此判负。
    // 不累积倒计时，并按正常速率回收已有倒计时。
    if (this.windTimer > 0 || this.windGrace > 0 || this.shakeTimer > 0 || this.shakeGrace > 0) {
      this.dangerTimer = Math.max(0, this.dangerTimer - dt * 2.5);
      if (this.dangerTimer <= 0) {
        this.lastDangerBeep = 0;
      }
      return;
    }
    let over: boolean = false;
    // 检测箱按半径收窄（球顶只算 DANGER_BOX_RATIO 半径），且只认「已经停住」的球：
    // 技能把球抛到空中时不算玩家堆太高，避免摇晃/漂浮瞬间误触倒计时
    const calm: number = this.layout.unit * DANGER_CALM_RATIO;
    const boxY: number = this.layout.dangerY;
    for (let i: number = 0; i < this.bodies.length; i++) {
      const b: Body = this.bodies[i];
      if (b.age > 0.6 && b.y - b.r * DANGER_BOX_RATIO < boxY && b.vy > -calm) {
        over = true;
        break;
      }
    }
    if (over) {
      const entering: boolean = this.dangerTimer <= 0;
      this.dangerTimer += dt;
      if (entering) {
        // 越线瞬间立刻告警，随后每过 1 秒补一次（对应 3-2-1 倒计时）
        this.sfx('danger');
      }
      const beep: number = Math.floor(this.dangerTimer);
      if (beep > this.lastDangerBeep) {
        this.lastDangerBeep = beep;
        if (!entering) {
          this.sfx('danger');
        }
      }
      if (this.dangerTimer >= DANGER_SECONDS) {
        this.gameOver();
      }
    } else {
      this.dangerTimer = Math.max(0, this.dangerTimer - dt * 2.5);
      if (this.dangerTimer <= 0) {
        // 脱离红线后重置警报节奏，下次越线重新从 3 秒开始倒数
        this.lastDangerBeep = 0;
      }
    }
  }

  gameOver(): void {
    if (this.score > this.highScore) {
      this.highScore = this.score;
    }
    if (this.score > this.save.highScore) {
      this.save.highScore = this.score;
    }
    this.save.maxTier = Math.max(this.save.maxTier, this.maxTier);
    this.save.save();
    this.sfx('result');
    this.setState(GameState.RESULT);
  }

  // ---------------------------------------------------------------- 特效与提示
  showToast(msg: string): void {
    this.toast = msg;
    this.toastTimer = 1.7;
  }

  private spawnPuff(x: number, y: number, color: string, count: number): void {
    if (this.particles.length > 110) {
      return;
    }
    for (let i: number = 0; i < count; i++) {
      const p: Particle = new Particle();
      const a: number = this.random() * Math.PI * 2;
      const sp: number = this.layout.unit * (0.25 + this.random() * 0.75);
      p.x = x;
      p.y = y;
      p.vx = Math.cos(a) * sp;
      p.vy = Math.sin(a) * sp - this.layout.unit * 0.18;
      p.life = 0.35 + this.random() * 0.35;
      p.maxLife = p.life;
      p.r = this.layout.s * (0.006 + this.random() * 0.010);
      p.color = color;
      this.particles.push(p);
    }
  }

  private addFloat(x: number, y: number, text: string, color: string, size: number): void {
    if (this.floatTexts.length > 14) {
      this.floatTexts.splice(0, 1);
    }
    const f: FloatText = new FloatText();
    f.x = x;
    f.y = y;
    f.text = text;
    f.color = color;
    f.size = size;
    f.life = 0.95;
    f.maxLife = 0.95;
    this.floatTexts.push(f);
  }

  private updateEffects(dt: number): void {
    this.toastTimer = Math.max(0, this.toastTimer - dt);
    this.flashTimer = Math.max(0, this.flashTimer - dt);
    this.lastGainTimer = Math.max(0, this.lastGainTimer - dt);
    const aliveP: Particle[] = [];
    for (let i: number = 0; i < this.particles.length; i++) {
      const p: Particle = this.particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += this.layout.unit * 1.5 * dt;
      p.vx *= 0.97;
      aliveP.push(p);
    }
    this.particles = aliveP;
    const aliveT: FloatText[] = [];
    for (let i: number = 0; i < this.floatTexts.length; i++) {
      const f: FloatText = this.floatTexts[i];
      f.life -= dt;
      f.y -= this.layout.s * 0.055 * dt;
      if (f.life > 0) {
        aliveT.push(f);
      }
    }
    this.floatTexts = aliveT;
  }

  /** 形状/尺寸变化后把已有刚体拉回新容器。 */
  private rehomeBodies(): void {
    for (let i: number = 0; i < this.bodies.length; i++) {
      const b: Body = this.bodies[i];
      b.r = radiusOf(b.level, this.layout.unit);
      this.constrainPos(b);
    }
  }

  /** 固定步长驱动：渲染帧率与物理解耦，掉帧时限制补帧数。 */
  advance(now: number, render: () => void): void {
    if (this.lastNow === 0) {
      this.lastNow = now;
    }
    let delta: number = (now - this.lastNow) / 1000;
    this.lastNow = now;
    if (delta > 0.08) {
      delta = 0.08;
    }
    this.accumulator += delta;
    let steps: number = 0;
    while (this.accumulator >= FIXED_DT && steps < MAX_STEPS_PER_FRAME) {
      this.step(FIXED_DT);
      this.accumulator -= FIXED_DT;
      steps++;
    }
    if (steps >= MAX_STEPS_PER_FRAME) {
      this.accumulator = 0; // 极端掉帧时丢弃积压，避免螺旋
    }
    render();
  }
}
