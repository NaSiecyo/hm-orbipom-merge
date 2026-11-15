import { common } from '@kit.AbilityKit';
import { GameState } from '../game/Config';
import { GameEngine } from '../game/GameEngine';
import { Renderer } from '../game/Renderer';
import { InputController } from '../game/Input';
import { Assets } from '../game/Assets';
import { SoundKit } from '../game/SoundKit';
import { FontKit } from '../game/FontKit';

/**
 * 全屏 Canvas 单页游戏。ArkUI 组件树保持极简：
 * 逐帧只做 Canvas 绘制，不触发组件重建，保证手表端帧率稳定。
 */
@Entry
@Component
struct Index {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private engine: GameEngine = new GameEngine();
  private renderer: Renderer = new Renderer();
  private input: InputController | null = null;
  private assets: Assets = new Assets();
  private sound: SoundKit = new SoundKit();
  private timerId: number = -1;
  private running: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.input = new InputController(this.engine);
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

    // 思源黑体注册：失败自动回退系统字体
    await FontKit.register($rawfile('font/source_han_cn.ttf'));

    // 原版素材：解码为 PixelMap 后交给 Canvas 渲染器
    this.assets.load(context);
    this.renderer.setAssets(this.assets);
    this.engine.onSound = (key: string) => {
      this.sound.play(key);
    };
    await this.sound.init(context);

    this.engine.relayoutCallback = () => {
      this.applySize(this.ctx.width, this.ctx.height);
    };
    await this.engine.save.init(context);
    this.engine.initSave(this.engine.save.highScore, this.engine.save.maxTier);
    this.applySize(this.ctx.width, this.ctx.height);
    this.startLoop();
  }

  aboutToDisappear(): void {
    this.stopLoop();
    if (this.input !== null) {
      this.input.dispose();
    }
    this.sound.release().catch(() => {});
  }

  onPageShow(): void {
    this.startLoop();
  }

  onPageHide(): void {
    this.engine.pause();
    this.stopLoop();
  }

  onBackPress(): boolean {
    if (this.engine.state === GameState.MENU || this.engine.state === GameState.RESULT) {
      return false; // 交还系统，允许退出应用
    }
    this.engine.onBack();
    return true;
  }

  private applySize(w: number, h: number): void {
    if (w > 0 && h > 0) {
      this.engine.applyLayout(w, h);
    }
  }

  private startLoop(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.engine.refreshButtons();
    this.timerId = setInterval(() => {
      const now: number = Date.now();
      this.engine.advance(now, () => {
        this.renderer.draw(this.ctx, this.engine, now);
      });
    }, 16);
  }

  private stopLoop(): void {
    this.running = false;
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .backgroundColor('#CFE3D9')
        .onReady(() => {
          this.applySize(this.ctx.width, this.ctx.height);
          this.startLoop();
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const wv = newValue.width;
          const hv = newValue.height;
          if (typeof wv === 'number' && typeof hv === 'number' && wv > 0 && hv > 0) {
            // 布局必须用 Canvas 内部像素尺寸：onAreaChange 给的是 vp（比像素小），
            // 直接拿来做布局会让背景只覆盖画布的一部分、其余漏出底色
            this.applySize(this.ctx.width, this.ctx.height);
          }
        })
        .onTouch((event: TouchEvent) => {
          if (this.input !== null) {
            this.input.onTouch(event);
          }
        })
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
        .onDigitalCrown((event: CrownEvent) => {
          if (this.input !== null) {
            this.input.onCrown(event.degree);
          }
          event.stopPropagation();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050A14')
  }
}
