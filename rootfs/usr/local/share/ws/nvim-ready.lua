-- Run by the image build in a headless nvim started with the dotfiles' config.
-- lazy.nvim installs the plugins before this runs, and the config starts
-- installing its treesitter parsers in the background. mason-lspconfig skips
-- its ensure_installed in headless nvim, so this installs those LSP servers
-- with Mason itself. It waits for everything the two ensure_installed lists
-- name, read from the plugins so nothing here repeats the dotfiles, and exits
-- non-zero, failing the build, if any are still missing after 20 minutes. The
-- plugin functions it reads are internals, pinned by lazy-lock.json; if a
-- lockfile update moves them, this fails rather than skip the installs.

-- The config sets up treesitter with vim.defer_fn; let that run first
vim.wait(1000)

local function wanted_parsers()
  return require('nvim-treesitter.configs').get_ensure_installed_parsers()
end

-- mason-lspconfig keeps lspconfig names (ts_ls); Mason installs packages
-- (typescript-language-server). The map is empty until Mason's registry loads.
local function wanted_servers()
  local names = require('mason-lspconfig.settings').current.ensure_installed
  local map = require('mason-lspconfig.mappings').get_mason_map().lspconfig_to_package
  local packages, unmapped = {}, {}
  for _, name in ipairs(names) do
    table.insert(map[name] and packages or unmapped, map[name] or name)
  end
  return packages, unmapped
end

local ok, parsers = pcall(wanted_parsers)
local ok2, names = pcall(function() return require('mason-lspconfig.settings').current.ensure_installed end)
if not (ok and ok2 and type(parsers) == 'table' and type(names) == 'table') then
  io.stderr:write("[nvim-ready] couldn't read ensure_installed from nvim-treesitter or mason-lspconfig\n")
  vim.cmd('cquit')
end

-- Starts a missing server's install (up to 3 tries) while checking for it
local attempts, gave_up = {}, false
local function install(registry, name)
  local pkg = registry.get_package(name)
  if pkg:is_installing() then
    return
  end
  if (attempts[name] or 0) >= 3 then
    gave_up = true
    return
  end
  attempts[name] = (attempts[name] or 0) + 1
  pkg:install({}, function(success, err)
    if not success then
      io.stderr:write(('[nvim-ready] installing %s failed (try %d): %s\n'):format(name, attempts[name], vim.inspect(err)))
    end
  end)
end

local function missing()
  local m = {}
  local packages, unmapped = wanted_servers()
  for _, name in ipairs(unmapped) do
    table.insert(m, 'unmapped:' .. name)
  end
  local registry = require('mason-registry')
  for _, name in ipairs(packages) do
    -- A package counts as installed while its install is still writing it
    local pkg = registry.get_package(name)
    if pkg:is_installing() then
      table.insert(m, name)
    elseif not pkg:is_installed() then
      table.insert(m, name)
      install(registry, name)
    end
  end
  for _, p in ipairs(wanted_parsers()) do
    if #vim.api.nvim_get_runtime_file('parser/' .. p .. '.so', false) == 0 then
      table.insert(m, 'parser:' .. p)
    end
  end
  return m
end

local last_report = 0
local done = vim.wait(20 * 60 * 1000, function()
  local m = missing()
  if #m > 0 and vim.uv.now() - last_report > 30000 then
    last_report = vim.uv.now()
    io.stderr:write('[nvim-ready] waiting for: ' .. table.concat(m, ' ') .. '\n')
  end
  return #m == 0 or gave_up
end, 2000)

if done and not gave_up then
  local packages = wanted_servers()
  io.stderr:write(('[nvim-ready] installed: %s; parsers: %s\n'):format(
    table.concat(packages, ' '), table.concat(wanted_parsers(), ' ')))
  vim.cmd('qa!')
else
  io.stderr:write(('[nvim-ready] %s; still missing: %s\n'):format(
    gave_up and 'gave up after 3 failed installs' or 'timed out', table.concat(missing(), ' ')))
  vim.cmd('cquit')
end
