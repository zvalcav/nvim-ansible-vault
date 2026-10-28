---@diagnostic disable: undefined-global
-- Test suite for lua/ansible-vault/core.lua

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)

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
-- 1. Core.parse_vault_password_file_from_cfg
-- =========================================================================
do
	-- Valid ansible.cfg with [defaults]
	local tmp_cfg = vim.fn.tempname() .. ".cfg"
	local f = io.open(tmp_cfg, "w")
	assert_true(f ~= nil, "failed to create temp cfg file")
	f:write("# Sample ansible configuration\n")
	f:write("[defaults]\n")
	f:write("inventory = ./hosts\n")
	f:write("vault_password_file = ~/.ansible/.vault_pass.txt\n")
	f:write("forks = 10\n")
	f:write("[privilege_escalation]\n")
	f:write("become = True\n")
	f:close()

	local parsed = Core.parse_vault_password_file_from_cfg(tmp_cfg)
	assert_true(parsed ~= nil, "parsed password file should not be nil")
	assert_true(parsed:match("%.ansible[/\\]%.vault_pass%.txt$") ~= nil, "should resolve expanded password path")
	os.remove(tmp_cfg)

	-- ansible.cfg with mixed-case [Defaults] and whitespace
	tmp_cfg = vim.fn.tempname() .. ".cfg"
	f = io.open(tmp_cfg, "w")
	f:write("[Defaults]\n")
	f:write("  vault_password_file   =   /etc/vault.key  \n")
	f:close()
	parsed = Core.parse_vault_password_file_from_cfg(tmp_cfg)
	assert_eq(parsed, "/etc/vault.key", "handles whitespace and mixed-case section")
	os.remove(tmp_cfg)

	-- ansible.cfg without vault_password_file in [defaults]
	tmp_cfg = vim.fn.tempname() .. ".cfg"
	f = io.open(tmp_cfg, "w")
	f:write("[defaults]\n")
	f:write("forks = 5\n")
	f:write("[other]\n")
	f:write("vault_password_file = /wrong/section/pw\n")
	f:close()
	parsed = Core.parse_vault_password_file_from_cfg(tmp_cfg)
	assert_eq(parsed, nil, "ignores vault_password_file in non-defaults section")
	os.remove(tmp_cfg)

	-- Non-existent cfg path
	parsed = Core.parse_vault_password_file_from_cfg("/nonexistent/path/ansible.cfg")
	assert_eq(parsed, nil, "returns nil for non-existent cfg")
end

-- =========================================================================
-- 2. Core.extract_encrypt_vault_ids
-- =========================================================================
do
	local output1 = "ERROR! The vault-ids prod,default are available to encrypt. Specify the vault-id..."
	local ids1 = Core.extract_encrypt_vault_ids(output1)
	assert_true(ids1 ~= nil, "should extract vault ids")
	assert_eq(#ids1, 2, "extracted 2 ids")
	assert_eq(ids1[1], "prod", "first id is prod")
	assert_eq(ids1[2], "default", "second id is default")

	-- Spaces and deduplication
	local output2 = "ERROR! the vault-ids dev,stage,dev are available to encrypt"
	local ids2 = Core.extract_encrypt_vault_ids(output2)
	assert_true(ids2 ~= nil, "should extract vault ids with lowercase the")
	assert_eq(#ids2, 2, "deduplicated ids")
	assert_eq(ids2[1], "dev", "first id is dev")
	assert_eq(ids2[2], "stage", "second id is stage")

	-- Nil or irrelevant output
	assert_eq(Core.extract_encrypt_vault_ids(""), nil, "empty output returns nil")
	assert_eq(Core.extract_encrypt_vault_ids("Random error without vault-ids"), nil, "irrelevant output returns nil")
	assert_eq(Core.extract_encrypt_vault_ids(nil), nil, "nil returns nil")
end

-- =========================================================================
-- 3. Core.check_is_file_vault
-- =========================================================================
do
	local vault_file = vim.fn.tempname()
	local f = io.open(vault_file, "w")
	f:write("$ANSIBLE_VAULT;1.1;AES256\n")
	f:write("6333333333333333333333333333333333333333\n")
	f:close()

	local is_vault = Core.check_is_file_vault({}, vault_file)
	assert_true(is_vault, "detects valid $ANSIBLE_VAULT header")
	os.remove(vault_file)

	local plain_file = vim.fn.tempname()
	f = io.open(plain_file, "w")
	f:write("foo: bar\n")
	f:close()

	is_vault = Core.check_is_file_vault({}, plain_file)
	assert_eq(is_vault, false, "plaintext file is not vault")
	os.remove(plain_file)

	is_vault = Core.check_is_file_vault({}, "/nonexistent/vault/file")
	assert_eq(is_vault, false, "nonexistent file returns false")
end

-- =========================================================================
-- 4. Core.find_inline_vault_block_at_cursor
-- =========================================================================
do
	local lines = {
		"---",
		"app:",
		"  name: my_app",
		"  # prettier-ignore",
		"  api_key: !vault |-",
		"          $ANSIBLE_VAULT;1.1;AES256",
		"          62313264626131343734323233323030",
		"          33383332333936353335333433363337",
		"  database:",
		"    host: localhost",
		"    password: !vault |",
		"      $ANSIBLE_VAULT;1.1;AES256",
		"      313233343536",
		"  other: value",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_current_buf(buf)

	-- Case 4a: Cursor on header line (line 5: api_key: !vault |-)
	vim.api.nvim_win_set_cursor(0, { 5, 4 })
	local block = Core.find_inline_vault_block_at_cursor(lines)
	assert_true(block ~= nil, "block found when cursor on header")
	assert_eq(block.key, "api_key", "key is api_key")
	assert_eq(block.start_line, 5, "start_line is 5")
	assert_eq(block.end_line, 8, "end_line is 8")
	assert_eq(#block.vault_content, 3, "vault_content has 3 lines")

	-- Case 4b: Cursor on # prettier-ignore line (line 4)
	vim.api.nvim_win_set_cursor(0, { 4, 2 })
	block = Core.find_inline_vault_block_at_cursor(lines)
	assert_true(block ~= nil, "block found when cursor on # prettier-ignore line")
	assert_eq(block.key, "api_key", "key is api_key")
	assert_eq(block.start_line, 5, "start_line points to vault header")

	-- Case 4c: Cursor inside ciphertext (line 7)
	vim.api.nvim_win_set_cursor(0, { 7, 12 })
	block = Core.find_inline_vault_block_at_cursor(lines)
	assert_true(block ~= nil, "block found when cursor inside ciphertext")
	assert_eq(block.key, "api_key", "key is api_key")
	assert_eq(block.start_line, 5, "start_line is 5")

	-- Case 4d: Second vault block (password: !vault |)
	vim.api.nvim_win_set_cursor(0, { 11, 6 })
	block = Core.find_inline_vault_block_at_cursor(lines)
	assert_true(block ~= nil, "block found for second vault")
	assert_eq(block.key, "password", "key is password")
	assert_eq(block.start_line, 11, "start_line is 11")
	assert_eq(block.end_line, 13, "end_line is 13")
	assert_eq(#block.vault_content, 2, "vault_content has 2 lines")

	-- Case 4e: Cursor on non-vault line (line 3: name: my_app)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })
	block = Core.find_inline_vault_block_at_cursor(lines)
	assert_eq(block, nil, "returns nil when cursor on regular line")

	-- Case 4f: Cursor on line 1 (---)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	block = Core.find_inline_vault_block_at_cursor(lines)
	assert_eq(block, nil, "returns nil on document header")
end

-- =========================================================================
-- 5. Core.get_vault_command
-- =========================================================================
do
	local cfg = {
		vault_executable = "/usr/local/bin/ansible-vault",
		vault_password_file = "/path/to/.vaultpass",
	}

	-- Basic view command
	local cmd = Core.get_vault_command(cfg, "view", "secret.yml")
	assert_eq(cmd[1], "/usr/local/bin/ansible-vault", "command uses custom executable")
	assert_eq(cmd[2], "view", "command action is view")
	assert_eq(cmd[3], "--vault-password-file", "includes password flag")
	assert_eq(cmd[4], "/path/to/.vaultpass", "includes password path")
	assert_eq(cmd[5], "secret.yml", "includes target file")

	-- Encrypt command with encrypt_vault_id option
	cmd = Core.get_vault_command(cfg, "encrypt", "secret.yml", { encrypt_vault_id = "prod" })
	assert_eq(cmd[2], "encrypt", "action is encrypt")
	assert_true(vim.tbl_contains(cmd, "--encrypt-vault-id"), "includes --encrypt-vault-id")
	assert_true(vim.tbl_contains(cmd, "prod"), "includes vault-id prod")

	-- Default executable fallback
	cmd = Core.get_vault_command({}, "decrypt", "file.yml")
	assert_eq(cmd[1], "ansible-vault", "default executable is ansible-vault")
	assert_eq(cmd[2], "decrypt", "action is decrypt")
end

-- =========================================================================
-- 6. Core.system
-- =========================================================================
do
	-- Run echo
	local res = Core.system({ "echo", "hello-vault" }, { text = true })
	assert_eq(res.code, 0, "echo command exited with code 0")
	assert_true(res.stdout:match("hello%-vault") ~= nil, "captured echo stdout")

	-- Run with stdin
	res = Core.system({ "cat" }, { stdin = "piped-data\n", text = true })
	assert_eq(res.code, 0, "cat with stdin exited with code 0")
	assert_true(res.stdout:match("piped%-data") ~= nil, "captured stdin through cat")

	-- Non-zero exit code
	res = Core.system({ "false" })
	assert_true(res.code ~= 0, "false exited with non-zero code")
end

print("CORE TESTS PASSED SUCCESSFULLY!")
if not vim.g.__test_runner then
	os.exit(0)
end
