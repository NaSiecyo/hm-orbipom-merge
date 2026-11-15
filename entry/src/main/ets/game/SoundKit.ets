/**
 * 原版音效（vendor/original/site/assets/audios）播放层。
 * 使用 MediaKit SoundPool 预加载短音效，低时延、可并发；
 * 音效资源放在 resources/rawfile/audio/，无需任何权限。
 * 初始化失败（不支持/资源缺失）时静默降级为无声，不影响游戏。
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const SFX_FILES: string[] = [
  'drop', 'merge', 'clear', 'wind', 'shake', 'swap',
  'danger', 'golden', 'result', 'click', 'select'
];

export class SoundKit {
  private pool: media.SoundPool | null = null;
  private ids: Map<string, number> = new Map<string, number>();
  enabled: boolean = true;

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      const info: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      this.pool = await media.createSoundPool(10, info);
      for (let i: number = 0; i < SFX_FILES.length; i++) {
        const key: string = SFX_FILES[i];
        const path: string = 'audio/' + key + '.mp3';
        try {
          const fd = context.resourceManager.getRawFdSync(path);
          const id: number = await this.pool.load(fd.fd, fd.offset, fd.length);
          this.ids.set(key, id);
          // 加载完成后立刻归还文件描述符，避免 11 个音效长期占用 fd
          try {
            context.resourceManager.closeRawFdSync(path);
          } catch (e) {
            // 忽略关闭失败
          }
        } catch (err) {
          // 单个音效加载失败不影响其余
        }
      }
    } catch (err) {
      this.pool = null;
    }
  }

  play(key: string): void {
    if (!this.enabled || this.pool === null) {
      return;
    }
    const id: number | undefined = this.ids.get(key);
    if (id === undefined) {
      return;
    }
    const params: media.PlayParameters = {
      loop: 0,
      rate: 1,
      leftVolume: 0.6,
      rightVolume: 0.6,
      priority: 0
    };
    try {
      this.pool.play(id, params, (error: BusinessError) => {});
    } catch (err) {
      // 播放失败静默忽略
    }
  }

  async release(): Promise<void> {
    if (this.pool !== null) {
      try {
        await this.pool.release();
      } catch (err) {
        // ignore
      }
      this.pool = null;
    }
  }
}
