---@diagnostic disable: undefined-global
if vim.g.loaded_ansible_vault then
	return
end
vim.g.loaded_ansible_vault = 1

require("ansible-vault").register_filetype_autocmd()
