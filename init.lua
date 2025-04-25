vim.g.mapleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		error("Error cloning lazy.nvim:\n" .. out)
	end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
})

local on_attach =
	function(event)
		local client = vim.lsp.get_client_by_id(event.data.client_id)
		local methods = vim.lsp.protocol.Methods

		---Utility for keymap creation.
		---@param lhs string
		---@param rhs string|function
		---@param opts string|table
		---@param mode? string|string[]
		local function keymap(lhs, rhs, opts, mode)
			opts = type(opts) == "string" and { desc = opts }
				or vim.tbl_extend("error", opts --[[@as table]], { buffer = bufnr })
			mode = mode or "n"
			vim.keymap.set(mode, lhs, rhs, opts)
		end

		---For replacing certain <C-x>... keymaps.
		---@param keys string
		local function feedkeys(keys)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", true)
		end

		---Is the completion menu open?
		local function pumvisible()
			return tonumber(vim.fn.pumvisible()) ~= 0
		end

		-- Enable completion and configure keybindings.
		if client.supports_method(methods.textDocument_completion) then
			vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })

			-- Use enter to accept completions.
			keymap("<cr>", function()
				return pumvisible() and "<C-y>" or "<cr>"
			end, { expr = true }, "i")

			-- Use slash to dismiss the completion menu.
			keymap("/", function()
				return pumvisible() and "<C-e>" or "/"
			end, { expr = true }, "i")

			-- Use <C-n> to navigate to the next completion or:
			-- - Trigger LSP completion.
			-- - If there's no one, fallback to vanilla omnifunc.
			keymap("<C-n>", function()
				if pumvisible() then
					feedkeys("<C-n>")
				else
					if next(vim.lsp.get_clients({ bufnr = 0 })) then
						vim.lsp.completion.trigger()
					else
						if vim.bo.omnifunc == "" then
							feedkeys("<C-x><C-n>")
						else
							feedkeys("<C-x><C-o>")
						end
					end
				end
			end, "Trigger/select next completion", "i")

			-- Buffer completions.
			keymap("<C-u>", "<C-x><C-n>", { desc = "Buffer completions" }, "i")

			-- Use <Tab> to accept a suggestion, navigate between snippet tabstops,
			-- or select the next completion.
			-- Do something similar with <S-Tab>.
			keymap("<Tab>", function()
				if pumvisible() then
					feedkeys("<C-n>")
				elseif vim.snippet.active({ direction = 1 }) then
					vim.snippet.jump(1)
				else
					feedkeys("<Tab>")
				end
			end, {}, { "i", "s" })
			keymap("<S-Tab>", function()
				if pumvisible() then
					feedkeys("<C-p>")
				elseif vim.snippet.active({ direction = -1 }) then
					vim.snippet.jump(-1)
				else
					feedkeys("<S-Tab>")
				end
			end, {}, { "i", "s" })

			-- Inside a snippet, use backspace to remove the placeholder.
			keymap("<BS>", "<C-o>s", {}, "s")
		end
		local map = function(keys, func, desc, mode)
			mode = mode or "n"
			vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end
		map("grn", vim.lsp.buf.rename, "[R]e[n]ame")
		map("gra", vim.lsp.buf.code_action, "[G]oto Code [A]ction", { "n", "x" })
		map("grr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
		map("gri", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
		map("grd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
		map("grD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
		map("gO", require("telescope.builtin").lsp_document_symbols, "Open Document Symbols")
		map("gW", require("telescope.builtin").lsp_workspace_symbols, "Open Workspace Symbols")
		map("grt", require("telescope.builtin").lsp_type_definitions, "[G]oto [T]ype Definition")

		-- This function resolves a difference between neovim nightly (version 0.11) and stable (version 0.10)
		---@param client vim.lsp.Client
		---@param method vim.lsp.protocol.Method
		---@param bufnr? integer some lsp support methods only in specific files
		---@return boolean
		local function client_supports_method(client, method, bufnr)
			if vim.fn.has("nvim-0.11") == 1 then
				return client:supports_method(method, bufnr)
			else
				return client.supports_method(method, { bufnr = bufnr })
			end
		end

		if
			client
			and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf)
		then
			local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.document_highlight,
			})

			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.clear_references,
			})

			vim.api.nvim_create_autocmd("LspDetach", {
				group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
				callback = function(event2)
					vim.lsp.buf.clear_references()
					vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
				end,
			})
		end

		if client and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
			map("<leader>th", function()
				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
			end, "[T]oggle Inlay [H]ints")
		end
	end,
	-- Diagnostic Config
	-- See :help vim.diagnostic.Opts
	vim.diagnostic.config({
		severity_sort = true,
		float = { border = "rounded", source = "if_many" },
		underline = { severity = vim.diagnostic.severity.ERROR },
		signs = vim.g.have_nerd_font and {
			text = {
				[vim.diagnostic.severity.ERROR] = "󰅚 ",
				[vim.diagnostic.severity.WARN] = "󰀪 ",
				[vim.diagnostic.severity.INFO] = "󰋽 ",
				[vim.diagnostic.severity.HINT] = "󰌶 ",
			},
		} or {},
		virtual_text = {
			source = "if_many",
			spacing = 2,
			format = function(diagnostic)
				local diagnostic_message = {
					[vim.diagnostic.severity.ERROR] = diagnostic.message,
					[vim.diagnostic.severity.WARN] = diagnostic.message,
					[vim.diagnostic.severity.INFO] = diagnostic.message,
					[vim.diagnostic.severity.HINT] = diagnostic.message,
				}
				return diagnostic_message[diagnostic.severity]
			end,
		},
	})

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = on_attach,
})

vim.filetype.add({ extension = { tree = "forester" } })

vim.lsp.config["forester-lsp"] = {
	cmd = { "forester", "lsp", "-vvv" },
	filetypes = { "forester" },
}

vim.lsp.enable("forester-lsp")
