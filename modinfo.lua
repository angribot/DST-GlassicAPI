local function zheng(zh, en)
	local LOC = {
		zh = zh,
		zht = zh,
	}
	return LOC[locale] or en
end

version = "4.2.13"
name = "Glassic API"
author = zheng("鸭子乐园", "Ducklantis")
-- stylua: ignore
changelog = zheng([[
- 模组调用API注册的配方与后处理现在归属调用方模组，不再归到GlassicAPI名下
- AddRecipe默认filter对齐官方：nounlock进工作站，builder_tag/builder_skill进角色，其余进模组
- CommonAction同时匹配code与mod_name，避免与其他模组的动作冲突
- SetOnequipSkinItem改为监听equipped事件，不再包装onequipfn
- 撤回4.2.12中"SetOnequipSkinItem补发unequipskinneditem事件"的改动；4.2.12新增的该事件会与自带此事件的官方prefab重复，导致装备记录被错误关闭
- 角色专属皮肤与test_fn改为同时满足，移除皮肤时一并清除专属标记
- MergeTranslationFromPO只应用本次合并的条目

最近更新：
- 修复CommonAction状态函数收不到当前动作的问题
- SetOnequipSkinItem在缺少equippable组件时跳过，并补发unequipskinneditem事件
- 修复MergeTranslationFromPO在目标语言未加载时崩溃的问题
- 减少皮肤校验与配方搜索中的重复计算
- 修复引擎已初始化模组皮肤时重复执行init_fn的问题
- 修复同一皮肤reskin被拒绝后未重新初始化的问题
- 修复模组皮肤初始化丢失skin_custom、默认build和容器打开状态的问题
- 修复CommonAction未同步mod_name导致动作RPC解析异常
- Floater优先使用官方SetSwapData接口，保留IA兼容回退
- 复用官方AddRecipeToFilter并补齐SetOnequipSkinItem参数转发
- 修复初始物品过滤会永久修改TUNING的问题
- 修复DefaultSkinSelectionPopup中角色专属皮肤过滤不生效
- reskin_tool对模组角色复用官方的can_cast_fn检查
- 修复发布器缺失的 mod.manifest
- 增加通用动作API。
- GetFullInventory增加一处条件判断。
- 修复一处崩溃。
- AnimState.GetSkinBuild现在会回落到Entity.GetSkinBuild。
- 为GlassicAPI.AddTech增加了一个传入参数。
- 官方皮肤不会被视为模组皮肤了。
- 调整了reskin_tool的can_cast_fn的后处理写法。
]], [[
- Recipes and post-init data registered through the API are now attributed to the calling mod instead of GlassicAPI
- AddRecipe default filters match the official ones: nounlock goes to the crafting station, builder_tag/builder_skill to the character, everything else to the mods filter
- CommonAction matches on code and mod_name, so actions from other mods no longer collide
- SetOnequipSkinItem listens on the equipped event instead of wrapping onequipfn
- Revert the unequipskinneditem push added in 4.2.12: official prefabs that already push it got a duplicate event, which closed the wrong worn-item record
- Character exclusive skins now also require their test_fn, and removing a skin clears its exclusive entry
- MergeTranslationFromPO only applies the entries it merged

Recent Changes:
- Fix CommonAction state functions not receiving the current action
- SetOnequipSkinItem skips prefabs without an equippable component and pushes unequipskinneditem
- Fix MergeTranslationFromPO crashing when the target language is not loaded
- Cut redundant work in skin validation and recipe search
- Fix duplicate mod skin init_fn calls when the engine already initialized the skin
- Fix mod skins not reinitializing after a rejected same-skin reskin
- Fix mod skin initialization dropping skin_custom, default build, and open-container state
- Fix CommonAction not copying mod_name, which broke action RPC resolution
- Prefer official Floater:SetSwapData while keeping the IA fallback
- Reuse AddRecipeToFilter and forward SetOnequipSkinItem arguments
- Fix starting item filter permanently modifying TUNING
- Fix character exclusive skin filter not working in DefaultSkinSelectionPopup
- Reuse official "can_cast_fn" checks for mod characters in "main/reskin_tool"
- Fix missing mod.manifest
- Add common action API.
- Add condition in fn GetFullInventory.
- Fix a crash.
- AnimState.GetSkinBuild will now fallback to Entity.GetSkinBuild.
- Add 2rd param for GlassicAPI.AddTech.
- Official skins are now ignored by "AddModSkin" fn.
- Rewrite "can_cast_fn" in "main/reskin_tool".
]])
description = zheng("版本: ", "Version: ")
		.. version
		.. zheng("\n\n更新内容:\n", "\n\nChanges:\n")
		.. changelog
		.. "\n"
		.. zheng("“帮助你快速创建一个模组以及制作皮肤。”", '"helps create mod and mod skins quickly."')

priority = 2147483647

api_version = 10
dst_compatible = true
all_clients_require_mod = true

icon_atlas = "images/modicon.xml"
icon = "modicon.tex"

folder_name = folder_name or "workshop-"
if not folder_name:find("workshop-") then
	name = name .. " - DEV"
end
