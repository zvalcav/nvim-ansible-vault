---@diagnostic disable: undefined-global
-- Test suite for filetype-limited plugin loading in nvim-ansible-vault

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)
vim.cmd("filetype plugin on")

-- Source the plugin entrypoint
vim.cmd("runtime plugin/ansible-vault.lua")

local function assert_eq(actual, expected, message)
	if actual ~= expected then
		print(string.format("ASSERTION FAILED: %s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
		os.exit(1)
	end
end

local function assert_true(cond, message)
	if not cond then
		print(string.format("ASSERTION FAILED: %s", message))
		os.exit(1)
	end
end

-- Test 1: YAML buffer has buffer-local commands and keymaps
local yaml_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(yaml_buf)
vim.bo[yaml_buf].filetype = "yaml"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command exists in yaml buffer")
assert_eq(vim.fn.exists(":AnsibleVaultEncryptFile"), 2, "AnsibleVaultEncryptFile command exists in yaml buffer")
assert_eq(vim.fn.exists(":AnsibleVaultDecryptFile"), 2, "AnsibleVaultDecryptFile command exists in yaml buffer")
assert_eq(vim.fn.exists(":AnsibleVaultEncryptInline"), 2, "AnsibleVaultEncryptInline command exists in yaml buffer")
assert_eq(vim.fn.exists(":AnsibleVaultDecryptInline"), 2, "AnsibleVaultDecryptInline command exists in yaml buffer")
assert_true(vim.fn.maparg("<leader>va", "n") ~= "", "<leader>va mapping exists in yaml buffer")
assert_true(vim.fn.maparg("<leader>vE", "n") ~= "", "<leader>vE mapping exists in yaml buffer")
assert_true(vim.fn.maparg("<leader>vD", "n") ~= "", "<leader>vD mapping exists in yaml buffer")
assert_true(vim.fn.maparg("<leader>ve", "n") ~= "", "<leader>ve mapping exists in yaml buffer")
assert_true(vim.fn.maparg("<leader>vd", "n") ~= "", "<leader>vd mapping exists in yaml buffer")

-- Test 2: yaml.ansible buffer has buffer-local commands and keymaps
local yaml_ansible_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(yaml_ansible_buf)
vim.bo[yaml_ansible_buf].filetype = "yaml.ansible"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command exists in yaml.ansible buffer")
assert_true(vim.fn.maparg("<leader>va", "n") ~= "", "<leader>va mapping exists in yaml.ansible buffer")

-- Test 3: ansible buffer has buffer-local commands and keymaps
local ansible_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(ansible_buf)
vim.bo[ansible_buf].filetype = "ansible"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command exists in ansible buffer")
assert_true(vim.fn.maparg("<leader>va", "n") ~= "", "<leader>va mapping exists in ansible buffer")

-- Test 4: Python buffer does NOT have commands or keymaps
local py_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(py_buf)
vim.bo[py_buf].filetype = "python"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 0, "AnsibleVaultAccess command absent in python buffer")
assert_eq(vim.fn.exists(":AnsibleVaultEncryptFile"), 0, "AnsibleVaultEncryptFile command absent in python buffer")
assert_eq(vim.fn.maparg("<leader>va", "n"), "", "<leader>va mapping absent in python buffer")
assert_eq(vim.fn.maparg("<leader>ve", "n"), "", "<leader>ve mapping absent in python buffer")

-- Test 5: Markdown buffer does NOT have commands or keymaps
local md_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(md_buf)
vim.bo[md_buf].filetype = "markdown"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 0, "AnsibleVaultAccess command absent in markdown buffer")
assert_eq(vim.fn.maparg("<leader>va", "n"), "", "<leader>va mapping absent in markdown buffer")

-- Test 6: Switching back to YAML buffer retains its commands and keymaps
vim.api.nvim_set_current_buf(yaml_buf)
assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command remains in yaml buffer after buffer switch")
assert_true(vim.fn.maparg("<leader>va", "n") ~= "", "<leader>va mapping remains in yaml buffer after buffer switch")

-- Test 7: Disabling default mappings via g:ansible_vault_no_default_mappings
vim.g.ansible_vault_no_default_mappings = 1
local no_map_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(no_map_buf)
vim.bo[no_map_buf].filetype = "yaml"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command exists when mappings disabled")
assert_eq(vim.fn.maparg("<leader>va", "n"), "", "<leader>va mapping absent when mappings disabled")
vim.g.ansible_vault_no_default_mappings = nil

-- Test 8: Custom filetypes configuration via setup()
local AV = require("ansible-vault")
AV.setup({
	filetypes = { "yaml.custom" },
})

local custom_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(custom_buf)
vim.bo[custom_buf].filetype = "yaml.custom"

assert_eq(vim.fn.exists(":AnsibleVaultAccess"), 2, "AnsibleVaultAccess command exists in custom configured filetype")
assert_true(vim.fn.maparg("<leader>va", "n") ~= "", "<leader>va mapping exists in custom configured filetype")

print("ALL TESTS PASSED SUCCESSFULLY!")
os.exit(0)
