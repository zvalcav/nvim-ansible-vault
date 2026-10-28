# nvim-ansible-vault

A Neovim plugin for editing Ansible Vault — supports inline YAML values and whole-file vaults.
Forked from <https://github.com/19bischof/nvim-ansible-vault/> to fix major bugs.

## Installation (Lazy.nvim)

```lua
{
  "zvalcav/nvim-ansible-vault",
  ft = { "yaml.ansible", "yaml", "ansible" },
  config = function()
    require("ansible-vault").setup({
      -- Target file types to attach commands and keymaps (default: { "yaml", "yaml.ansible", "ansible" })
      -- filetypes = { "yaml", "yaml.ansible", "ansible" },

      -- Omit ansible_cfg_directory to auto-detect nearest ansible.cfg (or .ansible.cfg)
      -- optionally set explicitly
      -- ansible_cfg_directory = "/path/to/ansible",

      -- optional if ansible_cfg_directory resolves vault-ids
      vault_password_file = "/path/to/your/.vaultpass",

      -- optional, defaults to "ansible-vault"
      -- relative path is possible too, for .venv/bin/ansible-vault
      vault_executable = "/absolute/path/to/ansible-vault",

      -- align inline vault ciphertext under !vault and add # prettier-ignore above
      format_inline_to_block = true,
    })
  end,
}
```

## Usage

Commands and default keybindings are automatically scoped buffer-locally to supported file types (`yaml`, `yaml.ansible`, and `ansible`), preventing command and keybinding collisions in other buffers (such as Python, C++, or Markdown).

### Default keybindings

| Key          | Action                                                           |
| ------------ | ---------------------------------------------------------------- |
| `<leader>va` | Open inline/file vault in a secure popup (auto-detect at cursor) |
| `<leader>vE` | Encrypt the entire current file                                  |
| `<leader>vD` | Decrypt the entire current file                                  |
| `<leader>ve` | Encrypt YAML scalar at cursor into inline `!vault \| -`          |
| `<leader>vd` | Decrypt inline `!vault` at cursor back into plaintext            |

These are provided by default on matching buffers. To disable the defaults, set `vim.g.ansible_vault_no_default_mappings = 1` before the plugin loads (see below).

### Commands

- `:AnsibleVaultAccess` — open inline/file vault at cursor in a popup
- `:AnsibleVaultEncryptFile` — encrypt the current file in-place
- `:AnsibleVaultDecryptFile` — decrypt the current file in-place
- `:AnsibleVaultEncryptInline` — encrypt the YAML scalar at cursor into inline vault
- `:AnsibleVaultDecryptInline` — decrypt inline vault at cursor into plaintext

### How it works

1. Place the cursor on the vault header (e.g. `password: !vault |`) or anywhere inside the vault block, then press `<leader>va`.
2. The plugin decrypts via `ansible-vault view` and opens an editable popup.
3. On save (`<C-s>` / `<CR>`), content is re‑encrypted using `ansible-vault encrypt_string` and written back.

### Popup controls

| Action            | Key(s)            |
| ----------------- | ----------------- |
| Save & encrypt    | `<C-s>` or `<CR>` |
| Cancel / close    | `<Esc>` or `q`    |
| Copy to clipboard | `y`               |
| Show help         | `?`               |

## Configuration

```lua
require("ansible-vault").setup({
  filetypes = { "yaml", "yaml.ansible", "ansible" },   -- target file types to attach commands and keymaps
  -- Omit ansible_cfg_directory to auto-detect nearest ansible.cfg (or .ansible.cfg)
  -- ansible_cfg_directory = "/path/to/ansible",       -- optionally set explicitly
  vault_password_file = "/path/to/ansible/.vaultpass", -- only needed if you have a single password and no ansible.cfg
  vault_executable = "ansible-vault",                  -- optional absolute path; defaults to this name
  format_inline_to_block = true,                       -- format inline ciphertext aligned with !vault and add # prettier-ignore above
  debug = false,                                       -- debug notifications (metadata only)
})
```

Notes:

- `filetypes` (default: `{ "yaml", "yaml.ansible", "ansible" }`): filetypes on which buffer-local commands and default keymaps are attached.
- `format_inline_to_block` (default: `true`): when encrypting inline (`<leader>ve`), aligns ciphertext directly beneath `!vault` and inserts `# prettier-ignore` above the key to prevent linters/formatters from flattening it. Decrypting inline (`<leader>vd`) automatically cleans up the preceding `# prettier-ignore` line. Cursor on the `# prettier-ignore` line is recognized for decryption.
- If `ansible_cfg_directory` is omitted, the plugin will automatically search upward from the current file to find `ansible.cfg` or `.ansible.cfg` and use that directory for commands. This enables multiple vault-ids without hardcoding a password file.
  - `vault_identity_list` (preferred for multiple vault-ids)
  - or `vault_password_file`

Example `ansible.cfg`:

```ini
[defaults]
vault_identity_list = default@~/.ansible/.vault_pass.txt,prod@~/.ansible/.vault_pass_prod.txt
# or, for a single password file
# vault_password_file = ~/.ansible/.vault_pass.txt
```

### Disabling default keymaps

Add this before the plugin loads, then set your own mappings:

```lua
vim.g.ansible_vault_no_default_mappings = 1
vim.keymap.set("n", "<leader>va", "<Cmd>AnsibleVaultAccess<CR>", { desc = "Ansible Vault: access at cursor" })
vim.keymap.set("n", "<leader>vE", "<Cmd>AnsibleVaultEncryptFile<CR>", { desc = "Ansible Vault: encrypt file" })
vim.keymap.set("n", "<leader>vD", "<Cmd>AnsibleVaultDecryptFile<CR>", { desc = "Ansible Vault: decrypt file" })
vim.keymap.set("n", "<leader>ve", "<Cmd>AnsibleVaultEncryptInline<CR>", { desc = "Ansible Vault: encrypt inline" })
vim.keymap.set("n", "<leader>vd", "<Cmd>AnsibleVaultDecryptInline<CR>", { desc = "Ansible Vault: decrypt inline" })
```

That's it! 🔐
