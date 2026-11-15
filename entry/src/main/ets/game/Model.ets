/**
 * 运行时数据模型。全部使用 class + 预声明字段，
 * 避免 ArkTS 静态类型检查下的动态对象布局。
 */

export class Body {
  id: number = 0;
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  r: number = 0;
  level: number = 1;
  dead: boolean = false;
  born: number = 0;        // 投放时刻（ms），用于红线宽限
  age: number = 0;
  pop: number = 0;         // 合成出现的缩放动画 0~1
  squash: number = 0;      // 碰撞形变
  mark: boolean = false;   // 战技选中的高亮
  windPhase: number = 0;   // 漂浮横向漂移相位（rad）
}

export class Particle {
  x: number = 0;
  y: number = 0;
  vx: number = 0;
  vy: number = 0;
  life: number = 0;
  maxLife: number = 0;
  r: number = 0;
  color: string = '#FFFFFF';
}

export class FloatText {
  x: number = 0;
  y: number = 0;
  life: number = 0;
  maxLife: number = 0;
  text: string = '';
  color: string = '#FFFFFF';
  size: number = 12;
}

export class UiButton {
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;
  label: string = '';
  id: number = 0;

  constructor(x: number, y: number, w: number, h: number, label: string, id: number) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.label = label;
    this.id = id;
  }

  hit(px: number, py: number): boolean {
    return px >= this.x - this.w / 2 && px <= this.x + this.w / 2 &&
      py >= this.y - this.h / 2 && py <= this.y + this.h / 2;
  }
}

export class SkillButton {
  x: number = 0;
  y: number = 0;
  r: number = 0;
  index: number = 0;

  hit(px: number, py: number): boolean {
    const dx: number = px - this.x;
    const dy: number = py - this.y;
    return dx * dx + dy * dy <= this.r * this.r * 1.35;
  }
}
