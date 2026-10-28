---@diagnostic disable: undefined-global
local Core = require("ansible-vault.core")
local Popup = require("ansible-vault.popup")

local M = {}

M.config = {
	vault_password_file = nil,
	ansible_cfg_directory = nil,
	vault_executable = "ansible-vault",
	format_inline_to_block = true,
	debug = false,
	filetypes = { "yaml", "yaml.ansible", "ansible" },
}

local vault_buffers = {}

local function is_target_filetype(ft)
	if not ft or ft == "" then
		return false
	end
	for _, target in ipairs(M.config.filetypes) do
		if ft == target then
			return true
		end
	end
	return false
end

function M.attach_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local function create_cmd(name, fn, desc)
		vim.api.nvim_buf_create_user_command(bufnr, name, fn, { desc = desc })
	end

	create_cmd("AnsibleVaultAccess", function()
		M.vault_access(bufnr)
	end, "Ansible Vault: access at cursor")
	create_cmd("AnsibleVaultEncryptFile", function()
		M.encrypt_current_file(bufnr)
	end, "Ansible Vault: encrypt file")
	create_cmd("AnsibleVaultDecryptFile", function()
		M.decrypt_current_file(bufnr)
	end, "Ansible Vault: decrypt file")
	create_cmd("AnsibleVaultEncryptInline", function()
		M.encrypt_inline_at_cursor(bufnr)
	end, "Ansible Vault: encrypt inline")
	create_cmd("AnsibleVaultDecryptInline", function()
		M.decrypt_inline_at_cursor(bufnr)
	end, "Ansible Vault: decrypt inline")

	if not vim.g.ansible_vault_no_default_mappings then
		local function map(lhs, rhs, desc)
			vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
		end
		map("<leader>va", "<Cmd>AnsibleVaultAccess<CR>", "Ansible Vault: access at cursor")
		map("<leader>vE", "<Cmd>AnsibleVaultEncryptFile<CR>", "Ansible Vault: encrypt file")
		map("<leader>vD", "<Cmd>AnsibleVaultDecryptFile<CR>", "Ansible Vault: decrypt file")
		map("<leader>ve", "<Cmd>AnsibleVaultEncryptInline<CR>", "Ansible Vault: encrypt inline")
		map("<leader>vd", "<Cmd>AnsibleVaultDecryptInline<CR>", "Ansible Vault: decrypt inline")
	end
end

function M.register_filetype_autocmd()
	local group = vim.api.nvim_create_augroup("AnsibleVaultFileType", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = M.config.filetypes,
		callback = function(args)
			M.attach_buffer(args.buf)
		end,
		desc = "Attach Ansible Vault commands and mappings to configured filetypes",
	})

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and is_target_filetype(vim.bo[buf].filetype) then
			M.attach_buffer(buf)
		end
	end
end

function M.setup(opts)
	vim.validate({ opts = { opts, "table", true } })
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	local group = vim.api.nvim_create_augroup("AnsibleVault", { clear = true })
	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		group = group,
		callback = function(args)
			vault_buffers[args.buf] = nil
		end,
	})
	M.register_filetype_autocmd()
end

local function fs_dirname(path)
	if vim.fs and vim.fs.dirname then
		return vim.fs.dirname(path)
	end
	return vim.fn.fnamemodify(path, ":h")
end

local function fs_basename(path)
	if vim.fs and vim.fs.basename then
		return vim.fs.basename(path)
	end
	return vim.fn.fnamemodify(path, ":t")
end

local function find_ansible_cfg(start_dir)
	if vim.fs and vim.fs.find then
		local matches = vim.fs.find({ "ansible.cfg", ".ansible.cfg" }, {
			upward = true,
			path = start_dir,
			type = "file",
			limit = 1,
		})
		return (matches and matches[1]) or nil
	end
	for _, name in ipairs({ "ansible.cfg", ".ansible.cfg" }) do
		local found = vim.fn.findfile(name, start_dir .. ";")
		if found and found ~= "" then
			return vim.fn.fnamemodify(found, ":p")
		end
	end
	return nil
end

-- Resolve the directory containing ansible.cfg by walking upward from file_path.
-- If M.config.ansible_cfg_directory is set, that takes precedence.
-- Returns (dir, cfg_file_path) so callers can also parse the cfg if needed.
local function resolve_ansible_cfg_for_file(file_path)
	if M.config.ansible_cfg_directory and M.config.ansible_cfg_directory ~= "" then
		local dir = vim.fn.expand(M.config.ansible_cfg_directory)
		local cfg_path = dir .. "/ansible.cfg"
		if vim.fn.filereadable(cfg_path) == 1 then
			return dir, cfg_path
		end
		return dir, nil
	end
	if not file_path or file_path == "" then
		return nil, nil
	end
	local start_dir = fs_dirname(file_path)
	local found = find_ansible_cfg(start_dir)
	if found then
		return fs_dirname(found), found
	end
	return nil, nil
end

-- Build a resolved config by auto-detecting ansible.cfg directory and vault_password_file.
local function resolve_config_for_file(file_path)
	local resolved_dir, cfg_file = resolve_ansible_cfg_for_file(file_path)
	local overrides = {}
	if resolved_dir and (not M.config.ansible_cfg_directory or M.config.ansible_cfg_directory == "") then
		overrides.ansible_cfg_directory = resolved_dir
	end
	if cfg_file and not M.config.vault_password_file then
		local pw_file = Core.parse_vault_password_file_from_cfg(cfg_file)
		if pw_file then
			overrides.vault_password_file = pw_file
		end
	end
	if next(overrides) then
		return vim.tbl_deep_extend("force", {}, M.config, overrides)
	end
	return M.config
end

function M.vault_access(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	if file_path == "" then
		vim.notify("Cannot access vault without a file path", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local vault_block = Core.find_inline_vault_block_at_cursor(lines)
	local vault_type = Core.VaultType.inline
	---@type string
	local vault_name = vault_block and vault_block.key or file_path

	vault_buffers[bufnr] = true
	local cfg = resolve_config_for_file(file_path)

	if not vault_block then
		local file_is_vault = Core.check_is_file_vault(cfg, file_path)
		if file_is_vault then
			vault_type = Core.VaultType.file
			vault_name = fs_basename(file_path)
		else
			vim.notify("No vault found at cursor position", vim.log.levels.WARN)
			return
		end
	end

	Core.debug(cfg, string.format("access vault_type=%s file=%s", vault_type, file_path))

	local decrypted_value, err
	if vault_type == Core.VaultType.inline then
		if not vault_block then
			vim.notify("Internal error: missing vault block for inline vault", vim.log.levels.ERROR)
			return
		end
		decrypted_value, err = Core.decrypt_inline_content(cfg, vault_block.vault_content)
	else
		decrypted_value, err = Core.decrypt_file_vault(cfg, file_path)
	end
	if not decrypted_value then
		-- Prompt for one-time password and retry once
		local function retry_with_password()
			-- Use secure hidden input
			local pw = vim.fn.inputsecret("Vault password (one-time): ")
			if not pw or pw == "" then
				vim.notify("Decryption cancelled (no password provided)", vim.log.levels.WARN)
				return
			end
			local retry_value, retry_err
			if vault_type == Core.VaultType.inline then
				if not vault_block or not vault_block.vault_content then
					vim.notify("Internal error: missing vault block for inline vault", vim.log.levels.ERROR)
					return
				end
				retry_value, retry_err = Core.decrypt_inline_content(cfg, vault_block.vault_content, { password = pw })
			else
				retry_value, retry_err = Core.decrypt_file_vault(cfg, file_path, { password = pw })
			end
			if not retry_value then
				vim.notify(
					"Failed to decrypt with provided password: " .. (retry_err or "unknown error"),
					vim.log.levels.ERROR
				)
				return
			end
			Popup.open(cfg, {
				bufnr = bufnr,
				file_path = file_path,
				vault_type = vault_type,
				vault_name = vault_name,
				decrypted_value = retry_value,
				vault_block = vault_block,
			})
		end
		-- Prefer prompting only on auth-related failures; best effort check
		if err and (err:match("[Pp]assword") or err:match("[Vv]ault")) then
			pcall(vim.cmd, "stopinsert")
			vim.schedule(retry_with_password)
			return
		end
		vim.notify("Failed to decrypt " .. vault_name .. ": " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end
	Core.debug(cfg, string.format("decrypted length=%d", #decrypted_value))

	Popup.open(cfg, {
		bufnr = bufnr,
		file_path = file_path,
		vault_type = vault_type,
		vault_name = vault_name,
		decrypted_value = decrypted_value,
		vault_block = vault_block,
	})
end

function M.encrypt_current_file(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	if file_path == "" then
		vim.notify("Cannot encrypt without a file path", vim.log.levels.ERROR)
		return
	end
	local cfg = resolve_config_for_file(file_path)
	Core.debug(cfg, string.format("encrypt_current_file (file only) file=%s", file_path))
	local cmd = Core.get_vault_command(cfg, "encrypt", file_path)
	local cwd = (cfg.ansible_cfg_directory and cfg.ansible_cfg_directory ~= "")
			and vim.fn.expand(cfg.ansible_cfg_directory)
		or nil
	local res = Core.system(cmd, { text = true, cwd = cwd })
	if res.code ~= 0 then
		local ids = Core.extract_encrypt_vault_ids((res.stderr or res.stdout or ""))
		if ids and #ids > 0 then
			pcall(vim.cmd, "stopinsert")
			vim.schedule(function()
				vim.ui.select(ids, { prompt = "Select vault-id for file encryption" }, function(choice)
					if not choice then
						vim.notify("Encryption cancelled (no vault-id selected)", vim.log.levels.WARN)
						return
					end
					local retry_cmd = Core.get_vault_command(cfg, "encrypt", file_path, { encrypt_vault_id = choice })
					local retry_res = Core.system(retry_cmd, { text = true, cwd = cwd })
					if retry_res.code ~= 0 then
						vim.notify(
							"Failed to encrypt file: " .. (retry_res.stderr or "unknown error"),
							vim.log.levels.ERROR
						)
						return
					end
					vim.notify("File encrypted successfully", vim.log.levels.INFO)
					vim.api.nvim_buf_call(bufnr, function()
						vim.cmd("edit!")
					end)
				end)
			end)
			return
		end
		vim.notify("Failed to encrypt file: " .. (res.stderr or "unknown error"), vim.log.levels.ERROR)
		return
	end
	vim.notify("File encrypted successfully", vim.log.levels.INFO)
	-- reload buffer to reflect on-disk encrypted content
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("edit!")
	end)
end

function M.decrypt_current_file(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	if file_path == "" then
		vim.notify("Cannot decrypt without a file path", vim.log.levels.ERROR)
		return
	end

	if vim.api.nvim_buf_get_option(bufnr, "modified") then
		vim.notify("Buffer has unsaved changes. Please save or discard them before decrypting.", vim.log.levels.ERROR)
		return
	end

	local cfg = resolve_config_for_file(file_path)
	Core.debug(cfg, string.format("decrypt_current_file (file only) file=%s", file_path))

	if not Core.check_is_file_vault(cfg, file_path) then
		vim.notify("File is not an Ansible Vault encrypted file", vim.log.levels.WARN)
		return
	end

	local ok, err = Core.decrypt_file(cfg, file_path)
	if not ok then
		local function retry_with_password()
			local pw = vim.fn.inputsecret("Vault password (one-time): ")
			if not pw or pw == "" then
				vim.notify("Decryption cancelled (no password provided)", vim.log.levels.WARN)
				return
			end
			local retry_ok, retry_err = Core.decrypt_file(cfg, file_path, { password = pw })
			if not retry_ok then
				vim.notify(
					"Failed to decrypt file: " .. (retry_err or "unknown error"),
					vim.log.levels.ERROR
				)
				return
			end
			vim.notify("File decrypted successfully", vim.log.levels.INFO)
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("edit!")
			end)
		end

		if err and (err:match("[Pp]assword") or err:match("[Vv]ault") or err:match("[Dd]ecryption failed")) then
			pcall(vim.cmd, "stopinsert")
			vim.schedule(retry_with_password)
			return
		end

		vim.notify("Failed to decrypt file: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	vim.notify("File decrypted successfully", vim.log.levels.INFO)
	-- reload buffer to reflect on-disk decrypted content
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("edit!")
	end)
end

---Encrypt the YAML scalar value at cursor into an inline vault block
---@param bufnr? integer
function M.encrypt_inline_at_cursor(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_nr = cursor[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local line = lines[line_nr]
	if not line then
		return
	end

	if line:match("^%s*#%s*prettier%-ignore%s*$") and line_nr < #lines then
		if lines[line_nr + 1]:match("^(%s*)([%w_-]+):%s*(.-)%s*$") then
			line_nr = line_nr + 1
			line = lines[line_nr]
		end
	end

	-- Match `key: value` on a single line, ignoring existing !vault
	local indent, key, value = line:match("^(%s*)([%w_-]+):%s*(.-)%s*$")
	if not indent or not key or not value or value == "" or value:match("!vault") then
		vim.notify("No simple YAML scalar at cursor to encrypt", vim.log.levels.WARN)
		return
	end

	local cfg = resolve_config_for_file(vim.api.nvim_buf_get_name(bufnr))
	local format_to_block = cfg.format_inline_to_block ~= false

	local function apply_inline_enc(vault_lines)
		local content_indent
		if format_to_block then
			content_indent = string.rep(" ", #indent + #key + 2)
		else
			content_indent = indent .. "  "
		end
		local new_header = string.format("%s%s: !vault |-", indent, key)

		local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local prev_line = line_nr > 1 and current_lines[line_nr - 1] or nil
		local has_prettier_ignore = prev_line
			and prev_line:match("^%s*#%s*prettier%-ignore%s*$") ~= nil
			and (prev_line:match("^(%s*)") or "") == indent

		local to_insert = {}
		if format_to_block and not has_prettier_ignore then
			table.insert(to_insert, indent .. "# prettier-ignore")
		end
		table.insert(to_insert, new_header)
		for _, l in ipairs(vault_lines) do
			table.insert(to_insert, content_indent .. l)
		end
		vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, to_insert)
		vim.notify("Inline value encrypted", vim.log.levels.INFO)
	end
	local vault_lines, err = Core.encrypt_content(cfg, value)
	if not vault_lines then
		local ids = Core.extract_encrypt_vault_ids(err or "")
		if ids and #ids > 0 then
			pcall(vim.cmd, "stopinsert")
			vim.schedule(function()
				vim.ui.select(ids, { prompt = "Select vault-id for inline encryption" }, function(choice)
					if not choice then
						vim.notify("Inline encryption cancelled", vim.log.levels.WARN)
						return
					end
					local retry_lines, retry_err = Core.encrypt_content(cfg, value, { encrypt_vault_id = choice })
					if not retry_lines then
						vim.notify(retry_err or "Failed to encrypt inline value", vim.log.levels.ERROR)
						return
					end
					apply_inline_enc(retry_lines)
				end)
			end)
			return
		end
		vim.notify(err or "Failed to encrypt inline value", vim.log.levels.ERROR)
		return
	end
	apply_inline_enc(vault_lines)
end

---Decrypt the inline vault block at cursor back into plaintext
---@param bufnr? integer
function M.decrypt_inline_at_cursor(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	if file_path == "" then
		vim.notify("Cannot decrypt without a file path", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local vault_block = Core.find_inline_vault_block_at_cursor(lines)
	if not vault_block then
		vim.notify("No inline vault block found at cursor position", vim.log.levels.WARN)
		return
	end

	local header_line = lines[vault_block.start_line] or ""
	local indent = header_line:match("^(%s*)") or ""
	local cfg = resolve_config_for_file(file_path)

	local function apply_decrypted(decrypted_text)
		local dec_lines = vim.split(decrypted_text, "\n", { plain = true })
		if #dec_lines > 0 and dec_lines[#dec_lines] == "" then
			table.remove(dec_lines)
		end

		local new_lines
		if #dec_lines <= 1 then
			local val = dec_lines[1] or ""
			new_lines = { string.format("%s%s: %s", indent, vault_block.key, val) }
		else
			new_lines = { string.format("%s%s: |-", indent, vault_block.key) }
			local content_indent = indent .. "  "
			for _, l in ipairs(dec_lines) do
				table.insert(new_lines, content_indent .. l)
			end
		end

		local replace_start = vault_block.start_line - 1
		if vault_block.start_line > 1 then
			local prev_line = lines[vault_block.start_line - 1]
			if prev_line and prev_line:match("^%s*#%s*prettier%-ignore%s*$") then
				local prev_indent = prev_line:match("^(%s*)") or ""
				if prev_indent == indent then
					replace_start = vault_block.start_line - 2
				end
			end
		end

		vim.api.nvim_buf_set_lines(bufnr, replace_start, vault_block.end_line, false, new_lines)
		vim.notify("Inline value decrypted", vim.log.levels.INFO)
	end

	local decrypted_value, err = Core.decrypt_inline_content(cfg, vault_block.vault_content)
	if not decrypted_value then
		local function retry_with_password()
			local pw = vim.fn.inputsecret("Vault password (one-time): ")
			if not pw or pw == "" then
				vim.notify("Decryption cancelled (no password provided)", vim.log.levels.WARN)
				return
			end
			local retry_val, retry_err =
				Core.decrypt_inline_content(cfg, vault_block.vault_content, { password = pw })
			if not retry_val then
				vim.notify(
					"Failed to decrypt inline value with provided password: " .. (retry_err or "unknown error"),
					vim.log.levels.ERROR
				)
				return
			end
			apply_decrypted(retry_val)
		end

		if err and (err:match("[Pp]assword") or err:match("[Vv]ault") or err:match("[Dd]ecryption failed")) then
			pcall(vim.cmd, "stopinsert")
			vim.schedule(retry_with_password)
			return
		end

		vim.notify("Failed to decrypt inline value: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	apply_decrypted(decrypted_value)
end

return M
