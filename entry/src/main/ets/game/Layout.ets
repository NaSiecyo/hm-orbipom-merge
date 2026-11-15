import { display } from '@kit.ArkUI';
import { GameState, SPAWN_MAX_TIER, radiusOf } from './Config';
import { SkillButton, UiButton } from './Model';

/**
 * 屏幕形状探测：优先使用 HarmonyOS 6 (API 18+) 的官方 screenShape，
 * 失败时退化为宽高比判断。应用内仍可手动切换圆/方布局。
 */
export class ScreenAdapter {
  static detectRound(w: number, h: number): boolean {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      if (d.screenShape === display.ScreenShape.ROUND) {
        return true;
      }
      if (d.screenShape === display.ScreenShape.RECTANGLE) {
        return false;
      }
    } catch (err) {
      return Math.abs(w - h) <= Math.min(w, h) * 0.06;
    }
    return Math.abs(w - h) <= Math.min(w, h) * 0.06;
  }
}

/**
 * 表盘布局（单位 vp，全部由实际 Canvas 尺寸推导）：
 *  - 圆形表盘：内容收进 0.475*S 安全圆内；中央「竖向高井」占 0.51S 宽 / 0.66S 高，
 *    四个战技按钮沿左右弧线布置（仿表壳侧键），顶部紧凑分数带、底部紧凑技力带。
 *  - 方形表盘：宽井占 83% 宽度，利用四角空间；战技水平排布在底部，图鉴/按钮更宽松。
 */
export class Layout {
  w: number = 0;
  h: number = 0;
  s: number = 0;
  round: boolean = true;
  safeR: number = 0;

  // 容器
  cx: number = 0;
  cy: number = 0;
  bowlR: number = 0;
  wellL: number = 0;
  wellT: number = 0;
  wellR: number = 0;
  wellB: number = 0;
  unit: number = 0;
  dangerY: number = 0;
  spawnY: number = 0;

  // HUD
  scoreX: number = 0;
  scoreY: number = 0;
  scoreFont: number = 0;
  highX: number = 0;
  highY: number = 0;
  highFont: number = 0;
  nextX: number = 0;
  nextY: number = 0;
  nextR: number = 0;
  energyX: number = 0;
  energyY: number = 0;
  energyW: number = 0;
  energyH: number = 0;

  skillButtons: SkillButton[] = [];
  buttons: UiButton[] = [];

  recompute(w: number, h: number, round: boolean): void {
    this.w = w;
    this.h = h;
    this.s = Math.min(w, h);
    this.round = round;
    this.safeR = this.s * 0.475;
    const S: number = this.s;

    if (round) {
      // 竖向窄井，四角仍落在安全圆内
      this.wellL = w / 2 - S * 0.255;
      this.wellR = w / 2 + S * 0.255;
      this.wellT = S * 0.165;
      this.wellB = S * 0.825;
    } else {
      this.wellL = w * 0.085;
      this.wellR = w * 0.915;
      this.wellT = h * 0.185;
      this.wellB = h * 0.775;
    }
    this.cx = (this.wellL + this.wellR) / 2;
    this.cy = (this.wellT + this.wellB) / 2;
    this.bowlR = (this.wellR - this.wellL) / 2;
    this.unit = this.wellR - this.wellL;
    this.dangerY = this.wellT + (this.wellB - this.wellT) * 0.22;
    this.spawnY = this.wellT + radiusOf(SPAWN_MAX_TIER, this.unit) + S * 0.014;

    // 顶部信息带
    this.scoreX = w / 2;
    this.scoreY = round ? S * 0.072 : h * 0.070;
    this.scoreFont = S * 0.092;
    this.highX = round ? w / 2 - S * 0.105 : w / 2;
    this.highY = round ? S * 0.143 : h * 0.128;
    this.highFont = S * 0.036;
    this.nextX = round ? w / 2 + S * 0.25 : w * 0.865;
    this.nextY = round ? S * 0.138 : h * 0.088;
    this.nextR = S * 0.042;

    // 技力条
    this.energyY = round ? S * 0.888 : h * 0.830;
    this.energyW = round ? S * 0.38 : w * 0.44;
    this.energyH = S * 0.024;
    this.energyX = w / 2;

    // 战技按钮
    this.skillButtons = [];
    const r: number = round ? S * 0.074 : S * 0.072;
    const px: number[] = round
      ? [S * 0.135, S * 0.135, w - S * 0.135, w - S * 0.135]
      : [w * 0.17, w * 0.39, w * 0.61, w * 0.83];
    const py: number[] = round
      ? [S * 0.375, S * 0.625, S * 0.375, S * 0.625]
      : [h * 0.912, h * 0.912, h * 0.912, h * 0.912];
    for (let i: number = 0; i < 4; i++) {
      const b: SkillButton = new SkillButton();
      b.index = i;
      b.r = r;
      b.x = px[i];
      b.y = py[i];
      this.skillButtons.push(b);
    }
  }

  /** 依据当前投放半径给出可用瞄准区间。 */
  aimRange(radius: number): number[] {
    const pad: number = radius + this.s * 0.008;
    return [this.wellL + pad, this.wellR - pad];
  }

  /** 每个界面状态的按钮（画布自绘 + 命中测试共用）。 */
  setButtons(state: GameState, roundLabel: string): UiButton[] {
    const S: number = this.s;
    const cx: number = this.w / 2;
    const out: UiButton[] = [];
    switch (state) {
      case GameState.MENU:
        out.push(new UiButton(cx, S * 0.565, S * 0.46, S * 0.125, '开始融合', 1));
        out.push(new UiButton(cx, S * 0.715, S * 0.36, S * 0.095, '融合图鉴', 2));
        out.push(new UiButton(cx, S * 0.845, S * 0.36, S * 0.085, roundLabel, 3));
        break;
      case GameState.PAUSED:
        out.push(new UiButton(cx, S * 0.435, S * 0.44, S * 0.105, '继续', 1));
        out.push(new UiButton(cx, S * 0.585, S * 0.44, S * 0.105, '重新开始', 2));
        out.push(new UiButton(cx, S * 0.735, S * 0.44, S * 0.105, '返回首页', 3));
        break;
      case GameState.CODEX:
        out.push(new UiButton(cx, S * 0.875, S * 0.32, S * 0.09, '返回', 1));
        break;
      case GameState.RESULT:
        out.push(new UiButton(cx, S * 0.685, S * 0.44, S * 0.105, '再来一局', 1));
        out.push(new UiButton(cx, S * 0.825, S * 0.38, S * 0.09, '返回首页', 2));
        break;
      case GameState.TARGET_CLEAR:
      case GameState.TARGET_SWAP:
        out.push(new UiButton(cx, S * 0.905, S * 0.30, S * 0.075, '取消', 1));
        break;
      default:
        break;
    }
    this.buttons = out;
    return out;
  }

  /** 图鉴 4x3 网格位置，圆形表盘下同样落在安全圆内。 */
  codexCell(index: number): number[] {
    const S: number = this.s;
    const col: number = index % 4;
    const row: number = Math.floor(index / 4);
    const x: number = this.w / 2 + (col - 1.5) * S * 0.205;
    const y: number = S * (0.315 + row * 0.165);
    return [x, y, S * 0.052];
  }
}
