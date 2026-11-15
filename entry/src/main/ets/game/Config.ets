/**
 * Orbipom Merge - 腕表重制版
 * 玩法参数集中配置。所有长度以 vp 为单位，物理以秒为单位，
 * 通过 Layout.unit 缩放，保证在不同表盘分辨率下手感一致。
 */

export enum GameState {
  MENU = 0,
  PLAYING = 1,
  PAUSED = 2,
  CODEX = 3,
  RESULT = 4,
  TARGET_CLEAR = 5,
  TARGET_SWAP = 6
}

export enum SkillType {
  CLEAR = 0,
  WIND = 1,
  SHAKE = 2,
  SWAP = 3
}

export interface Tier {
  level: number;
  name: string;
  radius: number;   // 相对 Layout.unit 的半径系数
  score: number;    // 合成出该级时获得的基础分
  main: string;
  light: string;
  dark: string;
}

/**
 * 原版共 11 种山团团（原活动文案：「总共有11种不同的山团团，参考图鉴，寻找黄金管理员」）。
 * 贴图一一对应 vendor/original/site/assets/imgs 的 01~11 主图组：
 * 赤角 / 狸斑 / 粉角 / 灰耳 / 橙帽 / 白绒 / 蓝耳 / 青冠 / 白羽 / 星眸 / 黄金管理员。
 * 两颗黄金管理员再次相撞 → 原版「终极融合」演出，双方清场并给巨额加分。
 */
export const TIERS: Tier[] = [
  { level: 1,  name: '赤角团团',   radius: 0.070, score: 1,  main: '#E6565C', light: '#FFC9CB', dark: '#8C2B36' },
  { level: 2,  name: '狸斑团团',   radius: 0.084, score: 3,  main: '#C9A87B', light: '#F5E3C6', dark: '#7A5C3B' },
  { level: 3,  name: '粉角团团',   radius: 0.099, score: 6,  main: '#F0A6C0', light: '#FFE0EC', dark: '#A85070' },
  { level: 4,  name: '灰耳团团',   radius: 0.115, score: 10, main: '#6E6E7C', light: '#C9C9D6', dark: '#3A3A48' },
  { level: 5,  name: '橙帽团团',   radius: 0.132, score: 15, main: '#F2A93B', light: '#FFE3A8', dark: '#A25C18' },
  { level: 6,  name: '白绒团团',   radius: 0.150, score: 21, main: '#EFE6C8', light: '#FFF9E8', dark: '#A09272' },
  { level: 7,  name: '蓝耳团团',   radius: 0.169, score: 28, main: '#F09AA0', light: '#FFDADD', dark: '#9C4F5E' },
  { level: 8,  name: '青冠团团',   radius: 0.189, score: 36, main: '#3E6C6B', light: '#A9CFCC', dark: '#203E40' },
  { level: 9,  name: '白羽团团',   radius: 0.210, score: 45, main: '#EEF1E8', light: '#FFFFFF', dark: '#9AA69A' },
  { level: 10, name: '星眸团团',   radius: 0.232, score: 55, main: '#E8E3F0', light: '#FFFFFF', dark: '#8B7CA6' },
  { level: 11, name: '黄金管理员', radius: 0.255, score: 88, main: '#F5C542', light: '#FFF0A8', dark: '#9A6A08' }
];

export const TIER_COUNT: number = 11;

/** 球体整体缩放：适当减小山团团，避免容器堆不下、难度过高 */
export const TIER_SCALE: number = 0.88;

// ---------- 核心玩法常量（对齐原版机制） ----------
export const FIXED_DT: number = 1 / 120;      // 固定物理步长
export const MAX_STEPS_PER_FRAME: number = 5; // 掉帧保护
export const SOLVER_ITERATIONS: number = 5;   // 碰撞位置松弛迭代（密堆需要多轮才解挤压）
export const MAX_BODIES: number = 42;         // 手表端上限，控制 O(n^2) 开销
export const SPAWN_MAX_TIER: number = 5;      // 随机投放 1~5 级
export const DANGER_SECONDS: number = 3.0;    // 红线倒计时（原版 3-2-1-0）
export const DROP_COOLDOWN: number = 0.34;    // 两次投放最小间隔
export const COMBO_WINDOW: number = 1.4;      // 连击窗口
export const COMBO_MAX: number = 8;

export const SKILL_COST: number[] = [1, 2, 3, 0];          // 舍弃/漂浮/摇晃/互换（互换不扣技力，靠累计消耗 6 点蓄能）
export const SKILL_NAME: string[] = ['舍弃', '漂浮', '摇晃', '互换'];
export const SKILL_ICON: string[] = ['✕', '↑', '≋', '⇄'];
export const SWAP_UNLOCK_SPENT: number = 6;    // 累计消耗 6 技力解锁命定互换

// 技力（对齐原版 skillPower）：energy = 已攒满的整格；energyRing = 当前这一格的进度环（0~12）
// 原版 ringSlots:12 / ringActivityMs:2000 / decayIntervalMs:1000 —— 只有「未满那一格」的进度会随空闲回落，
// 已攒满的整格永不衰减，所以第三格能真正存满。
export const ENERGY_RING_SLOTS: number = 12;   // 每满 12 环 +1 格
export const ENERGY_RING_IDLE: number = 2.0;   // 距上次合成超过该秒数才开始掉环
export const ENERGY_RING_DECAY: number = 1.0;  // 空闲时每秒掉多少环
export const ENERGY_MAX: number = 3.0;

// ---------- 协议·漂浮（WIND）：水位上涌 → 全部浮起 → 水位退去 → 落回 ----------
// 对齐原版实现（vendor/original 的 wind.fillMs / holdMs / drainMs + buoyancyPerMass + densityToWind）。
// 原版是「虚拟水面 + 浮力随浸没深度」的流体模型，而不是把重力调小：
// 水面从容器底部升起 → 球被浮力托离底部 → 浮到水面平衡悬停 → 水面退去 → 球自然落回。
// 原版是 Box2D 米制（mass、lightRadius、maxSpeed），此处按 unit(vp) 与 120Hz 固定步长换算成等效系数。
export const WIND_FILL: number = 0.8;         // 灌入：水面从容器底升到目标水位（秒）
export const WIND_HOLD: number = 2.0;         // 维持：水面停在目标高度，球浮在水面（秒）
export const WIND_DRAIN: number = 0.8;        // 抽回：水面退回容器底，球落回（秒）
export const WIND_SECONDS: number = WIND_FILL + WIND_HOLD + WIND_DRAIN;
export const WIND_LEVEL_RATIO: number = -0.35; // 目标水位高于容器顶 35% 容器高：球会冲出容器，甚至飞出屏幕，再落回
export const WIND_BUOY_MUL: number = 1.5;     // 满浸没浮力 = 重力 × 该系数（再除以密度权重 w，重的球升得慢）
export const WIND_RHO_SCALE: number = 1.32;   // 原版 rhoScale：把等级密度归一到 1 附近
export const WIND_LIGHT_MUL: number = 1.2;    // 轻球浮力倍率（原版 buoyancyLightMul）
export const WIND_HEAVY_MUL: number = 0.9;    // 重球浮力倍率（原版 buoyancyHeavyMul）
export const WIND_DRAG: number = 3.2;         // 漂浮期间流体阻尼（1/s），抑制过冲与来回漂
export const WIND_MAX_RISE: number = 3.0;     // 上浮速度上限 = unit * 该系数 (vp/s)
export const WIND_DRIFT: number = 0.55;       // 漂浮期间横向漂移加速度 = unit * 该系数 (vp/s²)
export const WIND_DRIFT_FREQ: number = 1.7;   // 横向漂移角频率 (rad/s)
export const WIND_GRACE: number = 0.9;
// ---------- 摇晃（SHAKE）----------
// 整堆同速上抛：统一速度下球与球之间没有相对速度，堆叠整体弹起再整体落下，
// 观感才是「一起被掀起」，也避免个别球冲顶被反复挤压。
export const SHAKE_SECONDS: number = 4.0;      // 屏抖持续（秒），比原版多 2.5s 的摇晃
export const SHAKE_AMP_RATIO: number = 0.036;  // 屏抖幅度 = 表盘尺寸 * 该系数
export const SHAKE_APEX_RATIO: number = -0.12; // 上抛顶点距容器顶 = 容器高 * 该系数（负值 = 冲到容器口之上）
export const SHAKE_RISE_RATIO: number = 0.55;  // 最小上抛高度 = 容器高 * 该系数（堆已很高时也保证有弹跳）
export const SHAKE_SPREAD: number = 1.15;      // 横向外散速度 = 竖直初速 * 该系数（加大后左右摇晃更明显）
export const SHAKE_TILT: number = 0.70;        // 基础左右倾角（rad，约 40°）：让左右动量与垂直动量相当
export const SHAKE_GRACE: number = 1.6;        // 结束后红线宽限（秒），等球落回再恢复判定
export const SHAKE_BOOST: number = 1.10;       // 初速额外加成，让整堆更猛地冲出容器口
export const SHAKE_BOX_RATIO: number = 0.85;   // 摇晃期间球与球的碰撞半径 = 该系数 * 绘制半径（球本身画多大不变）
export const SHAKE_JITTER: number = 0.16;      // 每球方向随机偏转幅度（rad，±0.16 ≈ ±9.2°）
export const SHAKE_VARY: number = 0.18;        // 每球力度随机幅度（±9%），方向随机但幅度一致

// ---------- 红线判定 ----------
// 检测箱按半径收窄，且只认「已经停住」的球：技能把球抛过线不算玩家堆太高。
export const DANGER_BOX_RATIO: number = 0.72;  // 判越线时球顶只算 72% 半径
export const DANGER_CALM_RATIO: number = 1.0;  // 竖直速度超过 unit*该值视为「还在飞」，不计入越线
        // 结束后红线宽限（秒），需覆盖抽回阶段的下落时间
export const WIND_DENSITY: number[] = [0.5, 0.6, 0.7, 0.8, 1.0, 1.02, 1.04, 1.06, 1.08, 1.1, 1.12];

// ---------- 堆叠稳定性（防深穿插 / 防自抖）----------
export const POS_CORRECTION: number = 0.92;    // 位置修正系数（每次迭代消掉的重叠比例）
export const BOUNCE_MIN_RATIO: number = 0.55;  // 法向接近速度 > unit * 该系数 才反弹，否则视为静置接触
export const REST_VEL_RATIO: number = 0.28;    // 有下方支撑且速度 < unit * 该系数 时速度清零
export const CONTACT_EPS_RATIO: number = 0.004; // 接触判定容差 = unit * 该系数 (vp)
export const SOLVER_SLOP_RATIO: number = 0.0008; // 最大重叠低于 unit * 该系数 时提前结束迭代
export const TIE_RATIO: number = 0.12;         // 两球横向偏移小于 (r1+r2)*该系数 时视为竖直共线，用法线偏置打破对称（同点连投不会叠成竖线）

// ---------- 物理常量（全部乘以 unit 做分辨率适配） ----------
export const GRAVITY_RATIO: number = 6.4;      // g = unit * 6.4
export const RESTITUTION: number = 0.12;
export const WALL_RESTITUTION: number = 0.18;
export const TANGENT_FRICTION: number = 0.20;  // 球与墙面/底面
// 球与球之间的切向摩擦：远小于墙面摩擦，堆叠才会自然塌落、滚开
export const BALL_FRICTION: number = 0.04;
export const AIR_DRAG: number = 0.55;
export const MAX_SPEED_RATIO: number = 9.0;

export function tierOf(level: number): Tier {
  let i: number = level - 1;
  if (i < 0) {
    i = 0;
  }
  if (i >= TIER_COUNT) {
    i = TIER_COUNT - 1;
  }
  return TIERS[i];
}

export function radiusOf(level: number, unit: number): number {
  return tierOf(level).radius * unit * TIER_SCALE;
}

/** 三角形数列分数：合成出 level 级时的基础分。 */
export function scoreOf(level: number): number {
  return Math.floor(level * (level + 1) / 2);
}

export function clamp(v: number, lo: number, hi: number): number {
  if (v < lo) {
    return lo;
  }
  if (v > hi) {
    return hi;
  }
  return v;
}
