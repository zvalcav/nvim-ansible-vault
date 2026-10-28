---@diagnostic disable: undefined-global
-- Test suite for lua/ansible-vault/popup.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)

local Popup = require("ansible-vault.popup")
local Core = require("ansible-vault.core")

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

-- =========================================================================
-- 1. Popup Window Creation & Buffer Options
-- =========================================================================
do
	local parent_buf = vim.api.nvim_create_buf(false, true)
	local parent_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(parent_win, parent_buf)

	local decrypted_text = "secret_password_123\nsecond_line"
	local config = { debug = false }

	Popup.open(config, {
		bufnr = parent_buf,
		file_path = "/tmp/test.yml",
		vault_type = Core.VaultType.inline,
		vault_name = "api_key",
		decrypted_value = decrypted_text,
		vault_block = {
			key = "api_key",
			start_line = 1,
			end_line = 3,
			vault_content = { "  $ANSIBLE_VAULT;1.1;AES256", "  12345" },
		},
	})

	local popup_win = vim.api.nvim_get_current_win()
	local popup_buf = vim.api.nvim_win_get_buf(popup_win)

	assert_true(popup_win ~= parent_win, "popup window is distinct from parent window")
	assert_true(vim.api.nvim_win_is_valid(popup_win), "popup window is valid")
	assert_true(vim.api.nvim_buf_is_valid(popup_buf), "popup buffer is valid")

	-- Check buffer settings
	assert_eq(vim.api.nvim_buf_get_option(popup_buf, "buftype"), "nofile", "buftype is nofile")
	assert_eq(vim.api.nvim_buf_get_option(popup_buf, "bufhidden"), "wipe", "bufhidden is wipe")
	assert_eq(vim.api.nvim_buf_get_option(popup_buf, "filetype"), "text", "filetype is text")
	assert_eq(vim.api.nvim_buf_get_option(popup_buf, "modifiable"), true, "modifiable is true")

	-- Check content in popup buffer
	local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
	assert_eq(#lines, 2, "popup buffer has 2 lines")
	assert_eq(lines[1], "secret_password_123", "line 1 matches decrypted value")
	assert_eq(lines[2], "second_line", "line 2 matches decrypted value")

	-- Check keymaps inside popup buffer
	local q_map = vim.fn.maparg("q", "n")
	assert_true(q_map ~= "", "'q' mapping exists in popup buffer")

	local esc_map = vim.fn.maparg("<Esc>", "n")
	assert_true(esc_map ~= "", "'<Esc>' mapping exists in popup buffer")

	local y_map = vim.fn.maparg("y", "n")
	assert_true(y_map ~= "", "'y' (yank) mapping exists in popup buffer")

	local help_map = vim.fn.maparg("?", "n")
	assert_true(help_map ~= "", "'?' (help) mapping exists in popup buffer")

	-- Close popup via buffer window close
	vim.api.nvim_win_close(popup_win, true)
	assert_eq(vim.api.nvim_win_is_valid(popup_win), false, "popup window closed cleanly")
end

-- =========================================================================
-- 2. Popup Save Handler for Inline Vault
-- =========================================================================
do
	local orig_encrypt_content = Core.encrypt_content
	local encrypt_called_with = nil
	Core.encrypt_content = function(_cfg, value, _opts)
		encrypt_called_with = value
		return { "$ANSIBLE_VAULT;1.1;AES256", "aabbcc" }, nil
	end

	local src_lines = {
		"vars:",
		"  api_key: !vault |-",
		"    $ANSIBLE_VAULT;1.1;AES256",
		"    old_ciphertext",
		"  other: value",
	}

	local parent_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(parent_buf, 0, -1, false, src_lines)
	local parent_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(parent_win, parent_buf)

	Popup.open({ debug = false }, {
		bufnr = parent_buf,
		file_path = "/tmp/test.yml",
		vault_type = Core.VaultType.inline,
		vault_name = "api_key",
		decrypted_value = "old_value",
		vault_block = {
			key = "api_key",
			start_line = 2,
			end_line = 4,
			vault_content = { "    $ANSIBLE_VAULT;1.1;AES256", "    old_ciphertext" },
		},
	})

	local popup_win = vim.api.nvim_get_current_win()
	local popup_buf = vim.api.nvim_win_get_buf(popup_win)

	-- Edit the popup content
	vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, { "new_secret_value" })

	-- Trigger <CR> (save & close) keymap
	vim.cmd("normal \r")

	assert_eq(encrypt_called_with, "new_secret_value", "Core.encrypt_content called with edited content")

	-- Check parent buffer lines: ciphertext replaced
	local updated_parent = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
	assert_eq(updated_parent[2], "  api_key: !vault |-", "vault header preserved")
	assert_eq(updated_parent[3], "    $ANSIBLE_VAULT;1.1;AES256", "new ciphertext line 1")
	assert_eq(updated_parent[4], "    aabbcc", "new ciphertext line 2")
	assert_eq(updated_parent[5], "  other: value", "following line preserved")

	Core.encrypt_content = orig_encrypt_content
end

print("POPUP TESTS PASSED SUCCESSFULLY!")
if not vim.g.__test_runner then
	os.exit(0)
end
