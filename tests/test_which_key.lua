---@diagnostic disable: undefined-global
-- Test suite for which-key.nvim integration in nvim-ansible-vault

local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo_root)

local AV = require("ansible-vault")

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
-- 1. Which-Key Absent (pcall fails gracefully)
-- =========================================================================
do
	package.loaded["which-key"] = nil
	-- Ensure require("which-key") will fail
	local orig_preload = package.preload["which-key"]
	package.preload["which-key"] = function()
		error("module 'which-key' not found")
	end

	local res = AV.register_which_key()
	assert_eq(res, false, "register_which_key returns false when which-key is absent")

	-- Clean up preload
	package.preload["which-key"] = orig_preload
	package.loaded["which-key"] = nil
end

-- =========================================================================
-- 2. Which-Key Present (wk.add receives exact spec table)
-- =========================================================================
do
	local registered_specs = nil
	local mock_wk = {
		add = function(specs)
			registered_specs = specs
		end,
	}
	package.loaded["which-key"] = mock_wk

	local res = AV.register_which_key()
	assert_eq(res, true, "register_which_key returns true when which-key is present")
	assert_true(registered_specs ~= nil, "which-key wk.add was invoked")
	assert_eq(#registered_specs, 6, "which-key registered 6 specs")

	-- Verify the exact specs
	assert_eq(registered_specs[1][1], "<leader>v", "spec 1 mapping is <leader>v")
	assert_eq(registered_specs[1].group, "Ansible vault", "spec 1 group is 'Ansible vault'")
	assert_eq(registered_specs[1].icon, "", "spec 1 icon is ''")

	assert_eq(registered_specs[2][1], "<leader>va", "spec 2 mapping is <leader>va")
	assert_eq(registered_specs[2].desc, "Access Vault at Cursor", "spec 2 desc")
	assert_eq(registered_specs[2].icon, "", "spec 2 icon is ''")

	assert_eq(registered_specs[3][1], "<leader>vE", "spec 3 mapping is <leader>vE")
	assert_eq(registered_specs[3].desc, "Encrypt Entire File", "spec 3 desc")
	assert_eq(registered_specs[3].icon, "", "spec 3 icon is ''")

	assert_eq(registered_specs[4][1], "<leader>vD", "spec 4 mapping is <leader>vD")
	assert_eq(registered_specs[4].desc, "Decrypt Entire File", "spec 4 desc")
	assert_eq(registered_specs[4].icon, "", "spec 4 icon is ''")

	assert_eq(registered_specs[5][1], "<leader>ve", "spec 5 mapping is <leader>ve")
	assert_eq(registered_specs[5].desc, "Encrypt Inline Value", "spec 5 desc")
	assert_eq(registered_specs[5].icon, "", "spec 5 icon is ''")

	assert_eq(registered_specs[6][1], "<leader>vd", "spec 6 mapping is <leader>vd")
	assert_eq(registered_specs[6].desc, "Decrypt Inline Value", "spec 6 desc")
	assert_eq(registered_specs[6].icon, "", "spec 6 icon is ''")
end

-- =========================================================================
-- 3. Setup Triggers which-key Registration
-- =========================================================================
do
	local setup_called = false
	package.loaded["which-key"] = {
		add = function(_)
			setup_called = true
		end,
	}

	AV.setup({})
	assert_true(setup_called, "AV.setup() automatically registers which-key mappings")
end

-- =========================================================================
-- 4. Buffer Attachment Triggers which-key Registration
-- =========================================================================
do
	local attach_called = false
	package.loaded["which-key"] = {
		add = function(_)
			attach_called = true
		end,
	}

	local test_buf = vim.api.nvim_create_buf(false, true)
	AV.attach_buffer(test_buf)
	assert_true(attach_called, "AV.attach_buffer() automatically registers which-key mappings")
	vim.api.nvim_buf_delete(test_buf, { force = true })
end

-- =========================================================================
-- 5. Disabled via g:ansible_vault_no_default_mappings
-- =========================================================================
do
	local wk_invoked = false
	package.loaded["which-key"] = {
		add = function(_)
			wk_invoked = true
		end,
	}

	vim.g.ansible_vault_no_default_mappings = 1
	local res = AV.register_which_key()
	assert_eq(res, false, "register_which_key returns false when no_default_mappings is set")
	assert_eq(wk_invoked, false, "wk.add not called when no_default_mappings is set")

	local test_buf = vim.api.nvim_create_buf(false, true)
	AV.attach_buffer(test_buf)
	assert_eq(wk_invoked, false, "attach_buffer does not call wk.add when no_default_mappings is set")
	vim.api.nvim_buf_delete(test_buf, { force = true })

	vim.g.ansible_vault_no_default_mappings = nil
end

-- =========================================================================
-- 6. Disabled via which_key = false Config Option
-- =========================================================================
do
	local wk_invoked = false
	package.loaded["which-key"] = {
		add = function(_)
			wk_invoked = true
		end,
	}

	AV.setup({ which_key = false })
	assert_eq(wk_invoked, false, "setup with which_key = false does not register which-key")

	local res = AV.register_which_key()
	assert_eq(res, false, "register_which_key returns false when config.which_key = false")

	-- Reset back to default
	AV.setup({ which_key = true })
end

-- =========================================================================
-- 7. Legacy which-key without wk.add handled gracefully
-- =========================================================================
do
	package.loaded["which-key"] = {
		register = function(_) end, -- old v2 api without add()
	}

	local res = AV.register_which_key()
	assert_eq(res, false, "register_which_key returns false when wk.add is missing")
end

-- Cleanup package.loaded
package.loaded["which-key"] = nil

print("WHICH-KEY INTEGRATION TESTS PASSED SUCCESSFULLY!")
if not vim.g.__test_runner then
	os.exit(0)
end
