# 卡牌确认队列

更新：2026-09-08。当前尚有 34/165 张逻辑卡牌保持 `provisional`。本清单只记录会改变规则实现的缺口；已经确认的内容会直接进入实现，不需要重复回答。

## 第一批：回复后可连续完成 20 张

| ID | 卡牌 | 仅需确认的规则 |
| --- | --- | --- |
| `frenzy_new` | 狂袭 | 目标本回合“受过伤害”是否包含使用者造成的伤害？ |
| `death_fight_new` | 死战 | 濒死是否指生命降至 0 或以下的瞬间；生命上限减多少？ |
| `assassination_order_new` | 刺杀令 | 弃置目标手牌由谁选择；每次攻击均可触发吗？ |
| `sleeve_arrow_new` | 袖箭 | 他人恢复生命时，能否在同一次恢复中由多个持有者触发？ |
| `samurai_sword_new` | 武士刀 | 首次实际伤害后的前进方向如何选择；路径伤害是否各 1 点且是否可响应？ |
| `guard_new` | 援护 | 可否指定自己；替承受哪些伤害；承受后获得多少护甲？ |
| `wind_raise_new` | 兴风 | 伤害后目标两格位移方向由谁选择；受阻是否造成碰撞伤害？ |
| `warhammer_new` | 重锤 | “将攻击伤害改为目标当前护甲”是否包括 0 护甲；替换整张攻击牌的每段伤害吗？ |
| `thunder_strike_new` | 雷霆冲击 | 前进两格后如何选择攻击目标；无法前进时能否继续攻击？ |
| `element_resonance_new` | 元素共鸣 | 可选的元素及各自对应状态；“连续同元素”按本回合还是跨回合？ |
| `explore_new` | 勘探 | 已确认至多两格、事件完成后才追加移动；请确认第一段移动使用一次选择路径还是逐格选择。 |
| `gold_panning_new` | 淘金 | 已确认可弃已装备装备；请确认弃装备时是进入弃牌堆且消耗其全部耐久吗。 |
| `exclusive_new` | 独享 | 已确认盲选各角色一张手牌；“结束出牌阶段”是否仍允许移动、购买和技能？ |
| `balance_new` | 权衡 | 已确认目标牌多时目标选择弃牌、少时从职业牌堆摸；请确认无职业牌时的兜底。 |

## 已有细节、但需要实现完整流程

以下卡的主要规则已从此前答复记录，尚缺多阶段 UI/事件链实现，不需要重新解释原效果：

`crossfire_new`, `planning_new`, `cleaver_new`, `broad_axe_new`, `thorn_armor_new`, `rhythm_armor_new`, `fear_shield_new`, `zero_day_bomb_new`, `lost_path_new`, `last_resort_new`, `black_hound_new`, `wolf_fang_new`, `decoy_new`, `counterstrike_new`, `guardian_ring_new`, `flame_cape_new`, `element_ring_new`, `twin_staff_new`, `resonance_robe_new`, `burning_cape_new`, `element_lens_new`, `tomb_robbery_new`, `explorer_hat_new`, `old_map_new`, `prospect_hammer_new`, `swap_new`, `consume_new`, `planning_ambitionist_new`, `wax_seal_new`, `secret_letter_new`, `verdict_new`, `star_robe_new`, `guard_unit_new`, `strange_face_new`, `pocket_watch_new`, `scatter_new`, `suppress_new`, `cover_fire_new`, `skirmish_new`, `charge_rifle_new`, `mortar_new`, `battle_map_new`。

## 回复格式

直接按以下格式回复即可，未列出的字段保留当前开发默认值：

```text
frenzy_new：包含自身造成的伤害
death_fight_new：生命降至0触发；上限减1
```

规则一旦确认，会从此文件移除、写入数据和自动测试，并解除对应 `provisional` 标记。
