import { GameState } from './Config';
import { UiButton } from './Model';
import { Layout } from './Layout';
import { GameEngine } from './GameEngine';

const LONG_PRESS_MS: number = 480;
const TAP_SLOP: number = 14;
const FLING_MS: number = 340;

/**
 * 手表端输入：基于 ArkUI TouchEvent 的轻量手势识别器。
 * 点按投放 / 横向拖动瞄准 / 长按暂停 / 上下滑图鉴 / 底部横滑微调瞄准 /
 * 双击「下一个」打开图鉴；旋转表冠通过 onDigitalCrown 精细瞄准。
 * 所有判定都在同一事件流内完成，避免多手势识别器抢占导致的重复投放。
 */
export class InputController {
  private engine: GameEngine;
  private down: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private lastX: number = 0;
  private lastY: number = 0;
  private startTime: number = 0;
  private moved: number = 0;
  private inWell: boolean = false;
  private inHud: boolean = false;
  private downSkill: number = -1;
  private downButton: UiButton | null = null;
  private longFired: boolean = false;
  private longTimer: number = -1;
  private lastTapTime: number = 0;
  private lastTapX: number = 0;
  private lastTapY: number = 0;

  constructor(engine: GameEngine) {
    this.engine = engine;
  }

  /** 页面销毁时清理长按计时器，避免回调落到已卸载的页面上。 */
  dispose(): void {
    if (this.longTimer >= 0) {
      clearTimeout(this.longTimer);
      this.longTimer = -1;
    }
    this.down = false;
    this.downButton = null;
    this.downSkill = -1;
  }

  onTouch(event: TouchEvent): void {
    // Up 事件在部分设备上 touches 为空，需回退到 changedTouches / 上一次坐标
    let x: number = this.lastX;
    let y: number = this.lastY;
    if (event.touches.length > 0) {
      x = event.touches[0].x;
      y = event.touches[0].y;
    } else if (event.changedTouches.length > 0) {
      x = event.changedTouches[0].x;
      y = event.changedTouches[0].y;
    } else if (event.type === TouchType.Down) {
      return;
    }
    this.lastX = x;
    this.lastY = y;
    if (event.type === TouchType.Down) {
      this.begin(x, y);
    } else if (event.type === TouchType.Move) {
      this.move(x, y);
    } else if (event.type === TouchType.Up) {
      this.end(x, y, false);
    } else if (event.type === TouchType.Cancel) {
      this.end(x, y, true);
    }
  }

  /** 旋转表冠：相对角度 → 投放位置微调（手表上比手指拖动更精准）。 */
  onCrown(degree: number): void {
    if (this.engine.state !== GameState.PLAYING) {
      return;
    }
    this.engine.nudgeAim(degree * this.engine.layout.s * 0.0018);
  }

  private begin(x: number, y: number): void {
    const L: Layout = this.engine.layout;
    this.down = true;
    this.startX = x;
    this.startY = y;
    this.lastX = x;
    this.lastY = y;
    this.startTime = Date.now();
    this.moved = 0;
    this.longFired = false;
    this.downSkill = -1;
    this.downButton = null;

    this.inWell = x >= L.wellL - L.s * 0.02 && x <= L.wellR + L.s * 0.02 &&
      y >= L.wellT - L.s * 0.02 && y <= L.wellB + L.s * 0.01;
    this.inHud = y > L.s * 0.74;

    for (let i: number = 0; i < L.skillButtons.length; i++) {
      if (L.skillButtons[i].hit(x, y)) {
        this.downSkill = i;
        break;
      }
    }
    for (let i: number = 0; i < L.buttons.length; i++) {
      if (L.buttons[i].hit(x, y)) {
        this.downButton = L.buttons[i];
        break;
      }
    }

    if (this.downSkill < 0 && this.downButton === null &&
      (this.engine.state === GameState.PLAYING ||
        this.engine.state === GameState.TARGET_CLEAR ||
        this.engine.state === GameState.TARGET_SWAP)) {
      this.longTimer = setTimeout(() => {
        if (this.down && !this.longFired && this.moved < TAP_SLOP) {
          this.longFired = true;
          this.engine.onBack();
        }
      }, LONG_PRESS_MS);
    }
  }

  private move(x: number, y: number): void {
    if (!this.down) {
      return;
    }
    const dx: number = x - this.startX;
    const dy: number = y - this.startY;
    this.moved = Math.max(this.moved, Math.sqrt(dx * dx + dy * dy));
    this.lastX = x;
    this.lastY = y;
    if (this.moved > TAP_SLOP && this.longTimer >= 0) {
      clearTimeout(this.longTimer);
      this.longTimer = -1;
    }
    if (this.engine.state === GameState.PLAYING && this.inWell && this.downSkill < 0) {
      this.engine.setAim(x);
    }
  }

  private end(x: number, y: number, cancelled: boolean): void {
    if (!this.down) {
      return;
    }
    this.down = false;
    if (this.longTimer >= 0) {
      clearTimeout(this.longTimer);
      this.longTimer = -1;
    }
    if (cancelled || this.longFired) {
      return;
    }
    const L: Layout = this.engine.layout;
    const now: number = Date.now();
    const dt: number = now - this.startTime;
    const dx: number = x - this.startX;
    const dy: number = y - this.startY;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    const isTap: boolean = dist < TAP_SLOP && dt < LONG_PRESS_MS;

    // 快速滑动（从按钮/战技图标起手的滑动不触发投放）
    if (!isTap && dt < FLING_MS && dist > L.s * 0.10 && dist / Math.max(1, dt) > 0.30) {
      if (this.downSkill >= 0 || this.downButton !== null) {
        return;
      }
      if (Math.abs(dy) >= Math.abs(dx)) {
        if (dy < 0) {
          if (this.engine.state === GameState.PLAYING) {
            this.engine.openCodex();
          } else if (this.engine.state === GameState.CODEX) {
            this.engine.closeCodex();
          } else if (this.engine.state === GameState.TARGET_CLEAR ||
            this.engine.state === GameState.TARGET_SWAP) {
            this.engine.cancelTargeting();
          }
        } else {
          if (this.engine.state === GameState.CODEX) {
            this.engine.closeCodex();
          } else if (this.engine.state === GameState.PLAYING) {
            this.engine.setAim(x);
            this.engine.drop();
          } else if (this.engine.state === GameState.TARGET_CLEAR ||
            this.engine.state === GameState.TARGET_SWAP) {
            this.engine.cancelTargeting();
          }
        }
      } else if (this.inHud) {
        // 底部横滑：相对微调瞄准，不投放（避免手指遮挡落点）
        if (this.engine.state === GameState.PLAYING) {
          this.engine.nudgeAim(dx * 0.85);
        }
      } else if (this.engine.state === GameState.PLAYING) {
        this.engine.setAim(x);
        this.engine.drop();
      }
      return;
    }

    if (!isTap) {
      // 拖动瞄准后松手投放
      if (this.engine.state === GameState.PLAYING && this.inWell && this.downSkill < 0) {
        this.engine.setAim(x);
        this.engine.drop();
        return;
      }
      if (this.inHud && this.engine.state === GameState.PLAYING) {
        this.engine.nudgeAim(dx * 0.85);
        return;
      }
      return;
    }

    // 双击「下一个」→ 融合图鉴
    const ndx: number = x - L.nextX;
    const ndy: number = y - L.nextY;
    const onNext: boolean = ndx * ndx + ndy * ndy <= L.nextR * L.nextR * 1.8;
    if (onNext && this.engine.state === GameState.PLAYING && now - this.lastTapTime < 320 &&
      Math.abs(x - this.lastTapX) < L.s * 0.06 &&
      Math.abs(y - this.lastTapY) < L.s * 0.06) {
      this.lastTapTime = 0;
      this.engine.openCodex();
      return;
    }
    this.lastTapTime = now;
    this.lastTapX = x;
    this.lastTapY = y;

    const st: GameState = this.engine.state;
    if (st === GameState.MENU || st === GameState.PAUSED ||
      st === GameState.CODEX || st === GameState.RESULT) {
      if (this.downButton !== null && this.downButton.hit(x, y)) {
        this.engine.handleButton(this.downButton.id);
      }
      return;
    }
    if (st === GameState.TARGET_CLEAR || st === GameState.TARGET_SWAP) {
      if (this.downButton !== null && this.downButton.hit(x, y)) {
        this.engine.handleButton(this.downButton.id);
        return;
      }
      this.engine.tapBody(x, y);
      return;
    }
    if (st === GameState.PLAYING) {
      if (this.downSkill >= 0 && L.skillButtons[this.downSkill].hit(x, y)) {
        this.engine.useSkill(this.downSkill);
        return;
      }
      if (onNext) {
        return;
      }
      if (this.inWell) {
        this.engine.setAim(x);
        this.engine.drop();
      }
    }
  }
}
