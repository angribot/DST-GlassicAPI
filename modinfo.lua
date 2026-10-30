local function zheng(zh, en)
	local LOC = {
		zh = zh,
		zht = zh,
	}
	return LOC[locale] or en
end

version = "4.3"
name = "Glassic API"
author = zheng("鸭子乐园", "Ducklantis")
changelog = zheng(
	[[
- RecipeSortBefore/RecipeSortAfter要求a、b为不同的非空字符串，无效参数立即报错，不再支持b为nil
- 指定filter但参照配方不在其中时，将待排序配方加入或移动到该filter末尾
- 配方排序后同步更新分类索引，并跳过不支持静态排序的filter
]],
	[[
- RecipeSortBefore/RecipeSortAfter require distinct, non-empty strings for a and b and immediately reject invalid arguments; nil is no longer supported for b
- When an explicit filter does not contain the reference recipe, add or move the recipe being sorted to the end of that filter
- Keep filter indices in sync after recipe sorting and skip filters that do not support static ordering
]]
)
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
