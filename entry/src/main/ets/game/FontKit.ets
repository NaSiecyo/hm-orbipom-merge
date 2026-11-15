/**
 * 中文字体：rawfile/font/source_han_cn.ttf（思源黑体 CN Regular）。
 * Canvas 的 ctx.font 只能引用「已注册」的字体族，因此启动时注册一次；
 * 注册失败（资源缺失 / 平台不支持）时自动回退系统默认字体，不影响任何功能。
 *
 * 字体源由调用方传入（$rawfile 只能在 UI 侧求值），保证本模块与资源系统解耦。
 */
import { font } from '@kit.ArkUI';

const FAMILY: string = 'SourceHanSansCN';

export class FontKit {
  private static registered: boolean = false;
  private static tried: boolean = false;

  static async register(src: Resource): Promise<void> {
    if (FontKit.tried) {
      return;
    }
    FontKit.tried = true;
    try {
      await font.registerFont({
        familyName: FAMILY,
        familySrc: src
      });
      FontKit.registered = true;
    } catch (err) {
      FontKit.registered = false;
    }
  }

  /** 供 ctx.font 直接拼接的字体族字段（含回退）。 */
  static css(): string {
    return FontKit.registered ? '"' + FAMILY + '", sans-serif' : 'sans-serif';
  }
}
