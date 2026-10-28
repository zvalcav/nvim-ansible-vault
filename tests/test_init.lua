---@diagnostic disable: undefined-global
-- Test suite for lua/ansible-vault/init.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)

local AV = require("ansible-vault")
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
-- 1. Setup & Configuration Resolution
-- =========================================================================
do
	AV.setup({
		vault_password_file = "/my/test/vaultpass",
		vault_executable = "/bin/custom-vault",
		format_inline_to_block = false,
		debug = true,
		filetypes = { "yaml", "yaml.ansible", "ansible", "yaml.custom" },
	})

	assert_eq(AV.config.vault_password_file, "/my/test/vaultpass", "vault_password_file configured")
	assert_eq(AV.config.vault_executable, "/bin/custom-vault", "vault_executable configured")
	assert_eq(AV.config.format_inline_to_block, false, "format_inline_to_block configured")
	assert_eq(AV.config.debug, true, "debug configured")
	assert_eq(#AV.config.filetypes, 4, "filetypes table merged")

	-- Reset back to defaults for remaining tests
	AV.setup({
		vault_password_file = nil,
		ansible_cfg_directory = nil,
		vault_executable = "ansible-vault",
		format_inline_to_block = true,
		debug = false,
		filetypes = { "yaml", "yaml.ansible", "ansible" },
	})
end

-- =========================================================================
-- 2. Inline Encryption with Block Formatting & prettier-ignore
-- =========================================================================
do
	-- Mock Core.encrypt_content to return deterministic ciphertext lines
	local orig_encrypt_content = Core.encrypt_content
	Core.encrypt_content = function(_cfg, value, _opts)
		if value == "mock_secret" then
			return {
				"$ANSIBLE_VAULT;1.1;AES256",
				"63313264626131343734323233323030",
				"33383332333936353335333433363337",
			}, nil
		end
		return nil, "mock encryption failure"
	end

	-- Test 2a: format_inline_to_block = true (default)
	AV.setup({ format_inline_to_block = true })
	local buf = vim.api.nvim_create_buf(false, true)
	local initial_lines = {
		"---",
		"vars:",
		"  password: mock_secret",
		"  other: 123",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_set_current_buf(buf)
	-- Cursor on line 3 (password: mock_secret)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })

	AV.encrypt_inline_at_cursor(buf)

	local result_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	-- Should have inserted # prettier-ignore above password
	assert_eq(result_lines[3], "  # prettier-ignore", "inserts # prettier-ignore above key")
	assert_eq(result_lines[4], "  password: !vault |-", "formats key with !vault |-")
	-- Indentation of ciphertext should align under !vault (indent=2 + #password=8 + 2 = 12 spaces)
	assert_eq(result_lines[5], "            $ANSIBLE_VAULT;1.1;AES256", "aligns ciphertext beneath !vault")

	-- Test 2b: Idempotent # prettier-ignore when already present
	local buf2 = vim.api.nvim_create_buf(false, true)
	local lines_with_ignore = {
		"---",
		"vars:",
		"  # prettier-ignore",
		"  token: mock_secret",
	}
	vim.api.nvim_buf_set_lines(buf2, 0, -1, false, lines_with_ignore)
	vim.api.nvim_set_current_buf(buf2)
	-- Cursor on line 4 (token: mock_secret)
	vim.api.nvim_win_set_cursor(0, { 4, 4 })

	AV.encrypt_inline_at_cursor(buf2)
	local result2 = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
	-- Should NOT duplicate # prettier-ignore
	assert_eq(result2[3], "  # prettier-ignore", "retains existing # prettier-ignore")
	assert_eq(result2[4], "  token: !vault |-", "formats token key")
	assert_true(result2[5]:match("^%s+%$ANSIBLE_VAULT;") ~= nil, "ciphertext present")

	-- Test 2c: Cursor on # prettier-ignore line recognizes the key below it
	local buf3 = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf3, 0, -1, false, lines_with_ignore)
	vim.api.nvim_set_current_buf(buf3)
	-- Cursor on line 3 (# prettier-ignore)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })

	AV.encrypt_inline_at_cursor(buf3)
	local result3 = vim.api.nvim_buf_get_lines(buf3, 0, -1, false)
	assert_eq(result3[4], "  token: !vault |-", "encrypts scalar when cursor is on prettier-ignore")

	-- Test 2d: format_inline_to_block = false (standard 2-space indent, no prettier-ignore)
	AV.setup({ format_inline_to_block = false })
	local buf4 = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf4, 0, -1, false, initial_lines)
	vim.api.nvim_set_current_buf(buf4)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })

	AV.encrypt_inline_at_cursor(buf4)
	local result4 = vim.api.nvim_buf_get_lines(buf4, 0, -1, false)
	assert_eq(result4[3], "  password: !vault |-", "no prettier-ignore inserted")
	assert_eq(result4[4], "    $ANSIBLE_VAULT;1.1;AES256", "standard 2-space indent")

	-- Test 2e: Attempting to encrypt line with existing !vault does nothing
	local lines_before_noop = vim.deepcopy(result4)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })
	AV.encrypt_inline_at_cursor(buf4)
	local lines_after_noop = vim.api.nvim_buf_get_lines(buf4, 0, -1, false)
	assert_eq(#lines_before_noop, #lines_after_noop, "noop when line already contains !vault")

	-- Restore original Core.encrypt_content
	Core.encrypt_content = orig_encrypt_content
end

-- =========================================================================
-- 3. Inline Decryption & Cleanup of prettier-ignore
-- =========================================================================
do
	local orig_decrypt_inline = Core.decrypt_inline_content
	Core.decrypt_inline_content = function(_cfg, _vault_content, _opts)
		return "decrypted_secret", nil
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local encrypted_lines = {
		"---",
		"vars:",
		"  # prettier-ignore",
		"  password: !vault |-",
		"            $ANSIBLE_VAULT;1.1;AES256",
		"            63313264626131343734323233323030",
		"  other: value",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, encrypted_lines)
	vim.api.nvim_set_current_buf(buf)
	-- Fake buffer name so file_path is valid
	vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".yml")

	-- Cursor on ciphertext line (line 5)
	vim.api.nvim_win_set_cursor(0, { 5, 12 })
	AV.decrypt_inline_at_cursor(buf)

	local decrypted_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	-- prettier-ignore line must be removed, restoring plain key: value
	assert_eq(decrypted_lines[3], "  password: decrypted_secret", "restored plain scalar and removed prettier-ignore")
	assert_eq(decrypted_lines[4], "  other: value", "surrounding lines preserved")

	-- Test multiline plaintext decryption
	Core.decrypt_inline_content = function(_cfg, _vault_content, _opts)
		return "line_one\nline_two\n", nil
	end

	local buf_multi = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_multi, 0, -1, false, encrypted_lines)
	vim.api.nvim_set_current_buf(buf_multi)
	vim.api.nvim_buf_set_name(buf_multi, vim.fn.tempname() .. ".yml")
	vim.api.nvim_win_set_cursor(0, { 4, 4 })

	AV.decrypt_inline_at_cursor(buf_multi)
	local multi_res = vim.api.nvim_buf_get_lines(buf_multi, 0, -1, false)
	assert_eq(multi_res[3], "  password: |-", "multiline decrypted value uses |-")
	assert_eq(multi_res[4], "    line_one", "multiline line 1 indented")
	assert_eq(multi_res[5], "    line_two", "multiline line 2 indented")

	Core.decrypt_inline_content = orig_decrypt_inline
end

-- =========================================================================
-- 4. File-Level Decryption Safety Check (Modified Buffer Protection)
-- =========================================================================
do
	local buf = vim.api.nvim_create_buf(true, false)
	local tmp_file = vim.fn.tempname() .. ".yml"
	local f = io.open(tmp_file, "w")
	f:write("$ANSIBLE_VAULT;1.1;AES256\n123456\n")
	f:close()

	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_name(buf, tmp_file)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$ANSIBLE_VAULT;1.1;AES256", "123456" })

	-- Mark buffer as modified (unsaved changes)
	vim.api.nvim_buf_set_option(buf, "modified", true)

	local orig_decrypt_file = Core.decrypt_file
	local decrypt_called = false
	Core.decrypt_file = function(_cfg, _file)
		decrypt_called = true
		return true, nil
	end

	-- Attempting to decrypt modified buffer must abort and not call Core.decrypt_file
	AV.decrypt_current_file(buf)
	assert_eq(decrypt_called, false, "decrypt_current_file aborted when buffer has unsaved changes")

	Core.decrypt_file = orig_decrypt_file
	os.remove(tmp_file)
end

print("INIT TESTS PASSED SUCCESSFULLY!")
if not vim.g.__test_runner then
	os.exit(0)
end
