local function zheng(zh, en)
	local LOC = {
		zh = zh,
		zht = zh,
	}
	return LOC[locale] or en
end

version = "4.2.11"
name = "Glassic API"
author = zheng("鸭子乐园", "Ducklantis")
-- stylua: ignore
changelog = zheng([[
- 修复引擎已初始化模组皮肤时重复执行init_fn的问题
- 修复同一皮肤reskin被拒绝后未重新初始化的问题

最近更新：
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
- Fix duplicate mod skin init_fn calls when the engine already initialized the skin
- Fix mod skins not reinitializing after a rejected same-skin reskin

Recent Changes:
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
