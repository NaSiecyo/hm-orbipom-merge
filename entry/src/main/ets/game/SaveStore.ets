import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 本地存档：最高分、图鉴解锁进度、表盘形状偏好。
 * 使用 Preferences 同步读写，不申请任何权限，纯本地离线可用。
 */
export class SaveStore {
  highScore: number = 0;
  maxTier: number = 1;
  shapeMode: number = 0; // 0 自动 / 1 强制圆形 / 2 强制方形
  private store: preferences.Preferences | null = null;

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, 'orbipom_watch_save');
      this.highScore = this.readInt('highScore', 0);
      this.maxTier = this.readInt('maxTier', 1);
      this.shapeMode = this.readInt('shapeMode', 0);
    } catch (err) {
      this.store = null;
    }
  }

  private readInt(key: string, def: number): number {
    if (this.store === null) {
      return def;
    }
    try {
      const v: number = this.store.getSync(key, def) as number;
      return typeof v === 'number' ? v : def;
    } catch (err) {
      return def;
    }
  }

  save(): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync('highScore', this.highScore);
      this.store.putSync('maxTier', this.maxTier);
      this.store.putSync('shapeMode', this.shapeMode);
      this.store.flush().catch(() => {});
    } catch (err) {
      // 存档失败不影响游戏进行
    }
  }
}
