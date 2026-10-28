---@diagnostic disable: undefined-global
-- Master test runner for nvim-ansible-vault

vim.g.__test_runner = true

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)

local test_suites = {
	"tests/test_filetype_loading.lua",
	"tests/test_core.lua",
	"tests/test_init.lua",
	"tests/test_popup.lua",
	"tests/test_which_key.lua",
}

print("==================================================")
print("Running nvim-ansible-vault test suites...")
print("==================================================")

local passed = 0
for _, suite in ipairs(test_suites) do
	local suite_path = repo_root .. "/" .. suite
	print("\n>> Executing: " .. suite)
	local ok, err = pcall(dofile, suite_path)
	if not ok then
		print("FAILED SUITE: " .. suite)
		print(tostring(err))
		os.exit(1)
	end
	passed = passed + 1
end

print("\n==================================================")
print(string.format("ALL %d TEST SUITES PASSED SUCCESSFULLY!", passed))
print("==================================================")

os.exit(0)
