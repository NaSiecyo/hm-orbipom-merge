/**
 * 原版素材加载层。
 * 所有图片来自 vendor/original/site/assets/imgs（原仓库为 Git LFS 指针，
 * 已从官方部署站点取得真实二进制），经等比例正方形化 / 尺寸压缩后放入 resources/base/media。
 *
 * 策略：首帧必需的少量贴图在 load() 中预解码，其余贴图在首次被绘制时才解码（惰性）。
 * 手表端可用内存紧张，11 级图鉴 + UI 贴图若全部常驻会白白占用数 MB。
 * PixelMap 生命周期与页面一致，不 release。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';

const ASSET_NAMES: string[] = [
  'bg_card',
  'bg_game',
  'bg_max_synth',
  'bg_menu',
  'bg_panel',
  'skill_clear',
  'skill_shake',
  'skill_swap',
  'skill_wind',
  'tier_01',
  'tier_02',
  'tier_03',
  'tier_04',
  'tier_05',
  'tier_06',
  'tier_07',
  'tier_08',
  'tier_09',
  'tier_10',
  'tier_11',
  'tier_icon_01',
  'tier_icon_02',
  'tier_icon_03',
  'tier_icon_04',
  'tier_icon_05',
  'tier_icon_06',
  'tier_icon_07',
  'tier_icon_08',
  'tier_icon_09',
  'tier_icon_10',
  'tier_icon_11',
  'ui_arrow',
  'ui_character',
  'ui_confetti',
  'ui_count_0',
  'ui_count_1',
  'ui_count_2',
  'ui_count_3',
  'ui_danger_line',
  'ui_danger_overlay',
  'ui_energy',
  'ui_frame',
  'ui_next',
  'ui_ribbon',
  'ui_score',
  'ui_skillbar',
  'ui_spark',
  'ui_star',
  'ui_title_deco',
  'ui_trophy',
  'endmins'
];

// $r() 需要字面量资源名，因此显式列出，避免依赖动态资源查找 API 的版本差异
const ASSET_RES: Resource[] = [
  $r('app.media.bg_card'),
  $r('app.media.bg_game'),
  $r('app.media.bg_max_synth'),
  $r('app.media.bg_menu'),
  $r('app.media.bg_panel'),
  $r('app.media.skill_clear'),
  $r('app.media.skill_shake'),
  $r('app.media.skill_swap'),
  $r('app.media.skill_wind'),
  $r('app.media.tier_01'),
  $r('app.media.tier_02'),
  $r('app.media.tier_03'),
  $r('app.media.tier_04'),
  $r('app.media.tier_05'),
  $r('app.media.tier_06'),
  $r('app.media.tier_07'),
  $r('app.media.tier_08'),
  $r('app.media.tier_09'),
  $r('app.media.tier_10'),
  $r('app.media.tier_11'),
  $r('app.media.tier_icon_01'),
  $r('app.media.tier_icon_02'),
  $r('app.media.tier_icon_03'),
  $r('app.media.tier_icon_04'),
  $r('app.media.tier_icon_05'),
  $r('app.media.tier_icon_06'),
  $r('app.media.tier_icon_07'),
  $r('app.media.tier_icon_08'),
  $r('app.media.tier_icon_09'),
  $r('app.media.tier_icon_10'),
  $r('app.media.tier_icon_11'),
  $r('app.media.ui_arrow'),
  $r('app.media.ui_character'),
  $r('app.media.ui_confetti'),
  $r('app.media.ui_count_0'),
  $r('app.media.ui_count_1'),
  $r('app.media.ui_count_2'),
  $r('app.media.ui_count_3'),
  $r('app.media.ui_danger_line'),
  $r('app.media.ui_danger_overlay'),
  $r('app.media.ui_energy'),
  $r('app.media.ui_frame'),
  $r('app.media.ui_next'),
  $r('app.media.ui_ribbon'),
  $r('app.media.ui_score'),
  $r('app.media.ui_skillbar'),
  $r('app.media.ui_spark'),
  $r('app.media.ui_star'),
  $r('app.media.ui_title_deco'),
  $r('app.media.ui_trophy'),
  $r('app.media.endmins')
];

/** 首帧 / 首屏就要用到的贴图，进游戏前一次性解码，避免开局掉帧。 */
const EAGER_NAMES: string[] = [
  'bg_game', 'bg_menu', 'bg_panel', 'bg_max_synth',
  'ui_score', 'ui_next', 'ui_energy', 'ui_danger_line', 'ui_danger_overlay',
  'skill_clear', 'skill_shake', 'skill_swap', 'skill_wind'
];

export class Assets {
  private maps: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private res: Map<string, Resource> = new Map<string, Resource>();
  private context: common.UIAbilityContext | null = null;
  ready: boolean = false;

  load(context: common.UIAbilityContext): void {
    this.context = context;
    this.res.clear();
    for (let i: number = 0; i < ASSET_NAMES.length; i++) {
      this.res.set(ASSET_NAMES[i], ASSET_RES[i]);
    }
    let loaded: number = 0;
    for (let i: number = 0; i < EAGER_NAMES.length; i++) {
      if (this.decode(EAGER_NAMES[i]) !== null) {
        loaded++;
      }
    }
    this.ready = loaded > 0;
  }

  /** 解码单张贴图并缓存；资源缺失或解码失败返回 null，由调用方回退自绘。 */
  private decode(name: string): image.PixelMap | null {
    const cached: image.PixelMap | undefined = this.maps.get(name);
    if (cached !== undefined) {
      return cached;
    }
    if (this.context === null) {
      return null;
    }
    const r: Resource | undefined = this.res.get(name);
    if (r === undefined) {
      return null;
    }
    try {
      const data: Uint8Array = this.context.resourceManager.getMediaContentSync(r);
      const source: image.ImageSource = image.createImageSource(data.buffer as ArrayBuffer);
      const pm: image.PixelMap = source.createPixelMapSync();
      this.maps.set(name, pm);
      return pm;
    } catch (err) {
      return null;
    }
  }

  get(name: string): image.PixelMap | null {
    return this.decode(name);
  }

  tier(level: number): image.PixelMap | null {
    const lv: number = level < 1 ? 1 : (level > 11 ? 11 : level);
    return this.get('tier_' + (lv < 10 ? '0' : '') + lv);
  }

  icon(level: number): image.PixelMap | null {
    const lv: number = level < 1 ? 1 : (level > 11 ? 11 : level);
    return this.get('tier_icon_' + (lv < 10 ? '0' : '') + lv);
  }

  skill(index: number): image.PixelMap | null {
    const keys: string[] = ['skill_clear', 'skill_wind', 'skill_shake', 'skill_swap'];
    if (index < 0 || index > 3) {
      return null;
    }
    return this.get(keys[index]);
  }

  count(n: number): image.PixelMap | null {
    const k: number = n < 0 ? 0 : (n > 3 ? 3 : n);
    return this.get('ui_count_' + k);
  }

  /** 统一绘制入口：图片缺失时返回 false，由调用方回退到自绘。 */
  static draw(ctx: CanvasRenderingContext2D, pm: image.PixelMap | null,
    x: number, y: number, w: number, h: number, alpha: number): boolean {
    if (pm === null) {
      return false;
    }
    ctx.save();
    // 与调用方已有的 globalAlpha 相乘（氛围层会先设置低透明度）
    ctx.globalAlpha = ctx.globalAlpha * alpha;
    ctx.drawImage(pm, x, y, w, h);
    ctx.restore();
    return true;
  }
}
