---
name: "崩坠牌局"
description: "深夜桌面上的快节奏缩圈卡牌乱斗"
colors:
  void: "oklch(0.10 0.00 0)"
  table: "oklch(0.16 0.01 255)"
  surface: "oklch(0.22 0.015 255)"
  line: "oklch(0.42 0.015 255)"
  ink: "oklch(0.94 0.01 90)"
  muted: "oklch(0.72 0.02 245)"
  primary: "oklch(0.50 0.15 330)"
  gold: "oklch(0.78 0.14 83)"
  danger: "oklch(0.68 0.14 25)"
  success: "oklch(0.66 0.12 150)"
typography:
  headline:
    fontFamily: "Noto Sans SC, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  body:
    fontFamily: "Noto Sans SC, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "0"
  label:
    fontFamily: "Noto Sans SC, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0"
rounded:
  sm: "4px"
  md: "8px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "10px 16px"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "16px"
---

# Design System: 崩坠牌局

## Overview

**Creative North Star: "深夜决斗桌"**

界面像一张在低照度房间中被集中照亮的实体游戏桌：棋盘、手牌和当前决策处于视觉中心，外围信息安静但可随时读取。深玫红只表示玩家操作与选中状态，金色只表示金币、关键奖励、焦点和胜利。

系统拒绝玻璃拟态、渐变文字、营销页大标题和无意义装饰动画。密度可以高，但相同概念必须保持相同位置、形状和用词。

## Colors

近黑无色背景承载氛围，冷灰层级组织信息；深玫红、奖励金、危险红和成功绿各自只承担一个语义。

- `void`：窗口背景和棋盘外区域。
- `table`：游戏桌和主工作区。
- `surface`：HUD、日志和弹层。
- `primary`：玩家可执行操作、焦点和选中状态，不超过单屏面积的 10%。
- `gold`：金币、关键奖励、键盘焦点和胜利状态，禁止用于普通装饰。
- `danger` / `success`：伤害、非法状态与恢复、确认反馈。

## Typography

全界面使用 Noto Sans SC 或系统无衬线后备字体。标题 28px/700，区块标题 20px/700，正文 16px/400，紧凑标签 14px/600；字距始终为 0。技能正文最多 70 个中文字符宽，超出后在详情层完整显示。

## Elevation

默认依靠明度差和实线边界分层，不使用大面积模糊阴影。只有事件、响应和设置弹层使用轻微的 8px 环境阴影，并配合背景遮罩表示阻塞状态。

## Components

- 按钮采用 4px 圆角，主操作使用深玫红填充和近白文字；焦点使用 2px 金色轮廓。
- 卡牌采用 6px 圆角，类型色仅出现在顶部图标与 3px 标识带，不使用嵌套卡片。
- 棋盘格保持固定正方形；悬停、可达和危险状态不得改变格子尺寸。
- 资源使用图标、数值和名称的组合；状态标记始终提供 tooltip。
- 弹层只用于必须先解决的事件、响应和设置，普通目标选择在棋盘内完成。

## Do's and Don'ts

### Do

- Do 使用固定位置呈现回合、行动数、移动机会和响应状态。
- Do 用颜色、图标与文字三种信号表达危险和状态。
- Do 将动画限制在 150-250ms，并提供即时替代。

### Don't

- Don't 使用紫蓝渐变、霓虹辉光或玻璃拟态。
- Don't 创建卡片套卡片、超过 8px 的常规卡片圆角或营销页式标题。
- Don't 让文字溢出、卡牌动态改变布局或仅靠颜色传达规则。
- Don't 给同一命令在不同界面使用不同按钮形状和用词。
