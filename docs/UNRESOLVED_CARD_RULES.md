# 待确认卡牌规则清单

更新：2026-09-04。此文件只列出无法由原文唯一推导的规则；例如“回复 2 点生命”“造成 1 点伤害并中毒”这类文字完整的基础牌，不需要重复确认，将直接进入实现和测试。

请按卡牌 ID 回复即可。未回复项目会继续保留 `provisional`，不会凭空补充规则。

## 范围、路径与位移

| 卡牌 | 原文 | 需要确认 |
| --- | --- | --- |
| `neutralize_new` 中和 | 至多 2 层中毒转移给其他角色 | 选择一名来源和一名目标，还是可分配给多个目标；目标没有中毒时是否仍可用？ |
| `explore_new` 勘探 | 移动 2 并触发落点神异格，然后可再移动 1 格 | “移动 2”是恰好两格还是至多两格；落点不是神异格时是否仍可用/仍可再移动；事件待选择时第二段移动如何衔接？ |
| `tomb_robbery_new` 盗墓 | 移动至 5x5 内普通格并触发其原神异格效果 | “原神异格效果”指随机事件牌，还是该普通格此前被覆盖的事件；移动是否要求正交路径？ |
| `scatter_new` 散射 | 横向 1x5 范围所有角色造成 1 点伤害 | 横向是施放者所在行还是目标所在行；是否可选方向；是否包含自己？ |
| `suppress_new` 压制 | 每点资源对 3x3 范围造成 1 点伤害 | 消耗的是当前全部体力和法力，还是玩家自选数量；3x3 的中心如何选择；是否包含施放者？ |
| `skirmish_new` 游击 | 未造成时移动后再造成 1 点 | “未造成”是被闪避/抵消/护甲完全抵消均算吗；移动距离和目标是否重新选择？ |

## 延迟、复制与条件规则

| 卡牌 | 原文 | 需要确认 |
| --- | --- | --- |
| `crossfire_new` 交锋 | 双方弃置攻击牌，按攻击力比较并造成伤害 | 双方如何选择弃牌；没有攻击牌时的结果；攻击力按牌面伤害、费用还是其他数值；平局结果？ |
| `planning_new` / `planning_ambitionist_new` 运筹 | 放至牌堆顶，下个抽到者摸两张并弃置 | 放入哪个牌堆；“下个抽到者”从任意牌堆抽到都触发吗；弃置的是运筹本身还是两张新摸牌？ |
| `last_resort_new` 破釜沉舟 | 弃置所有手牌后，视为使用一张本职业攻击牌 | 由玩家从哪个集合选择攻击牌；免费使用吗；被选牌是否需要目标/响应，是否受每局限次？ |
| `frenzy_new` 狂袭 | 目标本回合受过伤害时费用减 1 | 减少体力、法力中的哪一种；两种费用都有时优先顺序；是否包含自己造成的伤害？ |
| `death_fight_new` 死战 | 本回合首次濒死时改为失去生命上限并回复 1 | 生命上限减少多少；若上限已为 1；“濒死”是伤害使生命小于等于 0 的瞬间吗？ |
| `decoy_new` 替身 | 下回合开始前首次受伤时防止伤害并弃攻击者一张牌 | 是否防止真实伤害、状态伤害和崩坠伤害；攻击者的弃牌由谁选择；若攻击者无手牌？ |
| `counterstrike_new` 反戈一击 | 反弹下一张攻击牌且不可响应，反弹后前进 1 | 反弹是否改为原攻击者受全部效果；前进方向与时点；未被攻击时何时失效？ |
| `guard_new` 援护 | 替一名角色承受下一次伤害 | 可否选自己；承受何种伤害；持续至何时；承受后获得多少护甲？ |
| `mana_flow_new` 魔力回流 | 弃 1 张元素牌，回 1 法力并摸 1 | 哪些牌算元素牌；不能弃时是否不可用；可否弃装备？ |
| `gold_panning_new` 淘金 | 弃 1 获 2；弃装备改 3 | 可否弃已装备的装备，还是只能弃手牌装备实例？ |
| `swap_new` 移花接木 | 用一张手牌交换其他角色区域的一张牌 | “区域”包含手牌、装备槽、弃牌堆还是牌堆；双方如何选牌；可否交换装备？ |
| `consume_new` 蚕食 | 其他角色获得牌时可打出并获得其一张牌 | “获得牌”包括摸牌、市场、回收和偷取吗；作为响应是否消耗资源；从对方新获得牌中选还是任意手牌？ |
| `exclusive_new` 独享 | 从所有角色各获一张手牌，然后结束出牌阶段 | 牌由谁选择；没有手牌的角色跳过吗；结束出牌阶段是否仍可移动/购买/使用技能？ |
| `balance_new` 权衡 | 将另一角色手牌数调整至与你相同 | 目标牌多时弃牌由谁选；少时从哪个牌堆摸；购买保留区是否计入？ |
| `cover_fire_new` 掩护 | 他人成为攻击目标时视为对攻击者使用压制 | 这是主动设置的持续响应还是立即可用；覆盖谁；压制消耗的资源来自谁；多名持有者如何排序？ |

## 装备触发与防御边界

以下装备的主要文本明确，但需要统一触发时序、可选/强制、每回合次数和与崩坠/真实伤害的关系。请按 ID 回复补充规则：

`crowbar_new`, `zero_day_bomb_new`, `a_plus_new`, `thorn_armor_new`, `rhythm_armor_new`, `fear_shield_new`, `rock_bottom_new`, `living_wood_new`, `lost_path_new`, `heavy_blade_new`, `hell_armor_new`, `hell_collar_new`, `hell_forge_sword_new`, `dragon_slayer_new`, `black_hound_new`, `crimson_cape_new`, `wolf_fang_new`, `needle_new`, `shadow_charm_new`, `assassination_order_new`, `sleeve_arrow_new`, `shadow_blade_new`, `shuriken_kunai_new`, `flying_shoes_new`, `samurai_sword_new`, `assassin_dagger_new`, `shield_axe_guardian_new`, `endless_line_new`, `guardian_ring_new`, `wind_raise_new`, `bedrock_new`, `warhammer_new`, `serpent_blade_new`, `flame_cape_new`, `element_ring_new`, `poison_bottle_new`, `twin_staff_new`, `resonance_robe_new`, `burning_cape_new`, `element_lens_new`, `explorer_hat_new`, `gold_magnet_new`, `gold_pick_new`, `old_map_new`, `prospect_hammer_new`, `trench_coat_new`, `wax_seal_new`, `secret_letter_new`, `verdict_new`, `star_robe_new`, `guard_unit_new`, `strange_face_new`, `pocket_watch_new`, `hunter_longbow_new`, `overlimit_pistol_new`, `charge_rifle_new`, `catapult_new`, `mortar_new`, `scope_new`, `battle_map_new`.

## 事件

仍有未唯一确定的事件规则已单独标为 provisional：`qingquan_one_move`, `qingquan_many_solutions`, `qingquan_quick_hands`, `qingquan_gardening`, `guitar_analysis_one_new`, `guitar_analysis_two_new`, `guitar_analysis_three_new`, `orange_yogurt_rice_new`, `madmen_cult_new`, `berserker_wizard`, `deep_space_wizard`, `shengyue_wizard`, `tianyan_wizard`, `exiled_diviner`, `map_master_new`, `border_patrol`, `locust_disaster`, `saint_relic`, `pilot_new`, `surge_market_new`, `alliance_memory_bank`, `mountain_elder`, `mind_reader`, `revolutionary_remnants_new`, `drunk_psychotic`, `dark_dungeon`, `king_eastward`.

事件中最需要补充的通用定义是：“重铸”“临时被动”“视为使用”“一张/一种牌”“造成伤害大于 2 的牌”“回复生命大于 2 的牌”以及“技能封锁”的精确执行方式。
