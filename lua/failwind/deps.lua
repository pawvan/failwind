--- *failwind.deps* Plugin manager
--- *FailwindDeps*
---
--- MIT License Copyright (c) 2024 Evgeni Chasnovski
---
--- ==============================================================================
---
--- Features:
---
--- - Manage plugins utilizing Git and built-in |packages| with these actions:
---     - Add plugin to current session, download if absent. See |FailwindDeps.add()|.
---     - Update with/without confirm, with/without parallel download of new data.
---       See |FailwindDeps.update()|.
---     - Delete unused plugins with/without confirm. See |FailwindDeps.clean()|.
---     - Get / set / save / load snapshot. See `FailwindDeps.snap_*()` functions.
---
---     All main actions are available both as Lua functions and user commands
---     (see |FailwindDeps-commands|).
---
--- - Minimal yet flexible plugin |FailwindDeps-plugin-specification|:
---     - Plugin source.
---     - Name of target plugin directory.
---     - Checkout target: branch, commit, tag, etc.
---     - Monitor branch to track updates without checking out.
---     - Dependencies to be set up prior to the target plugin.
---     - Hooks to call before/after plugin is created/changed.
---
--- - Helpers implementing two-stage startup: |FailwindDeps.now()| and |FailwindDeps.later()|.
---   See |FailwindDeps-overview| for how to implement basic lazy loading with them.
---
--- What it doesn't do:
---
--- - Manage plugins which are developed without Git. The suggested approach is
---   to create a separate package (see |packages|).
---
--- - Provide ways to completely remove or update plugin's functionality in
---   current session. Although this is partially doable, it can not be done
---   in full (yet) because plugins can have untraceable side effects
---   (autocmmands, mappings, etc.).
---   The suggested approach is to restart Nvim.
---
--- Sources with more details:
--- - |FailwindDeps-overview|
--- - |FailwindDeps-plugin-specification|
--- - |FailwindDeps-commands|
---
--- # Dependencies ~
---
--- For most of its functionality this plugin relies on `git` CLI tool.
--- See https://git-scm.com/ for more information about how to install it.
--- Actual knowledge of Git is not required but helpful.
---
--- # Setup ~
---
--- This module needs a setup with `require('failwind.deps').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `FailwindDeps`
--- which you can use for scripting or manually (with `:lua FailwindDeps.*`).
---
--- See |FailwindDeps.config| for `config` structure and default values.
---
--- You can override runtime config settings locally to buffer inside
--- `vim.b.minideps_config` which should have same structure as
--- `FailwindDeps.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - 'folke/lazy.nvim':
---     - More feature-rich and complex.
---     - Uses table specification with dedicated functions to add plugins,
---       while this module uses direct function call approach
---       (calling |FailwindDeps.add()| ensures that plugin is usable).
---     - Uses version tags by default, while this module is more designed towards
---       tracking branches. Using tags is possible too (see |FailwindDeps-overview|).
---
--- - 'savq/paq-nvim':
---     - Overall less feature-rich than this module (by design).
---     - Uses array of plugin specifications inside `setup()` call to define which
---       plugins should be installed. Requires separate `:PaqInstall` call to
---       actually install them. This module ensures installation on first load.
---
--- - 'junegunn/vim-plug':
---     - Written in Vimscript, while this module is in Lua.
---     - Similar approach to defining and installing plugins as 'savq/paq-nvim'.
---     - Has basic lazy-loading built-in, while this module does not (by design).
---
--- # Highlight groups ~
---
--- Highlight groups are used inside confirmation buffers after
--- default |FailwindDeps.update()| and |FailwindDeps.clean()|.
---
--- * `FailwindDepsChangeAdded`   - added change (commit) during update.
--- * `FailwindDepsChangeRemoved` - removed change (commit) during update.
--- * `FailwindDepsHint`          - various hints.
--- * `FailwindDepsInfo`          - various information.
--- * `FailwindDepsMsgBreaking`   - message for (conventional commit) breaking change.
--- * `FailwindDepsPlaceholder`   - placeholder when there is no valuable information.
--- * `FailwindDepsTitle`         - various titles.
--- * `FailwindDepsTitleError`    - title when plugin had errors during update.
--- * `FailwindDepsTitleSame`     - title when plugin has no changes to update.
--- * `FailwindDepsTitleUpdate`   - title when plugin has changes to update.
---
--- To change any highlight group, modify it directly with |:highlight|.

--- # Directory structure ~
---
--- This module uses built-in |packages| to make plugins usable in current session.
--- It works with "pack/failwind" package inside `config.path.package` directory.
---
--- By default "opt" subdirectory is used to install optional plugins which are
--- loaded on demand with |FailwindDeps.add()|.
--- Non-optional plugins in "start" subdirectory are supported but only if moved
--- there manually after initial install. Use it if you know what you are doing.
---
--- # Add plugin ~
---
--- Use |FailwindDeps.add()| to add plugin to current session. Supply plugin's URL
--- source as a string or |FailwindDeps-plugin-specification| in general. If plugin is
--- not present in "pack/failwind" package, it will be created (a.k.a. installed)
--- before processing anything else.
---
--- The recommended way of adding a plugin is by calling |FailwindDeps.add()| in the
--- |init.lua| file (make sure |FailwindDeps.setup()| is called prior): >lua
---
---   local add = FailwindDeps.add
---
---   -- Add to current session (install if absent)
---   add({
---     source = 'neovim/nvim-lspconfig',
---     -- Supply dependencies near target plugin
---     depends = { 'williamboman/mason.nvim' },
---   })
---
---   add({
---     source = 'nvim-treesitter/nvim-treesitter',
---     -- Use 'master' while monitoring updates in 'main'
---     checkout = 'master',
---     monitor = 'main',
---     -- Perform action after every checkout
---     hooks = { post_checkout = function() vim.cmd('TSUpdate') end },
---   })
---   -- Possible to immediately execute code which depends on the added plugin
---   require('nvim-treesitter.configs').setup({
---     ensure_installed = { 'lua', 'vimdoc' },
---     highlight = { enable = true },
---   })
--- <
--- NOTE:
--- - To increase performance, `add()` only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.checkout` state.
---   Update or modify plugin state explicitly (see later sections).
---
--- # Lazy loading ~
---
--- Any lazy-loading is assumed to be done manually by calling |FailwindDeps.add()|
--- at appropriate time. This module provides helpers implementing special safe
--- two-stage loading:
--- - |FailwindDeps.now()| safely executes code immediately. Use it to load plugins
---   with UI necessary to make initial screen draw.
--- - |FailwindDeps.later()| schedules code to be safely executed later, preserving
---   order. Use it (with caution) for everything else which doesn't need
---   precisely timed effect, as it will be executed some time soon on one of
---   the next event loops. >lua
---
---   local now, later = FailwindDeps.now, FailwindDeps.later
---
---   -- Safely execute immediately
---   now(function() vim.cmd('colorscheme randomhue') end)
---   now(function() require('mini.statusline').setup() end)
---
---   -- Safely execute later
---   later(function() require('mini.pick').setup() end)
--- <
--- # Update ~
---
--- To update plugins from current session with new data from their sources,
--- use |:DepsUpdate|. This will download updates (utilizing multiple cores) and
--- show confirmation buffer. Follow instructions at its top to finish an update.
---
--- NOTE: This updates plugins on disk which most likely won't affect current
--- session. Restart Nvim to have them properly loaded.
---
--- # Modify ~
---
--- To change plugin's specification (like set different `checkout`, etc.):
--- - Update corresponding |FailwindDeps.add()| call.
--- - Run `:DepsUpdateOffline <plugin_name>`.
--- - Review changes and confirm.
--- - Restart Nvim.
---
--- NOTE: if `add()` prior used a single source string, make sure to convert
--- its argument to `{ source = '<previous_argument>', checkout = '<state>'}`
---
--- # Snapshots ~
---
--- Use |:DepsSnapSave| to save state of all plugins from current session into
--- a snapshot file (see `config.path.snapshot`).
---
--- Use |:DepsSnapLoad| to load snapshot. This will change (without confirmation)
--- state on disk. Plugins present in both snapshot file and current session
--- will be affected. Restart Nvim to see the effect.
---
--- NOTE: loading snapshot does not change plugin's specification defined inside
--- |FailwindDeps.add()| call. This means that next update might change plugin's state.
--- To make it permanent, freeze plugin in target state manually.
---
--- # Freeze ~
---
--- Modify plugin's specification to have `checkout` pointing to a static
--- target: tag, state (commit hash), or 'HEAD' (to freeze in current state).
---
--- Frozen plugins will not receive updates. You can monitor any new changes from
--- its source by "subscribing" to `monitor` branch which will be shown inside
--- confirmation buffer after |:DepsUpdate|.
---
--- Example: use `checkout = 'v0.10.0'` to freeze plugin at tag "v0.10.0" while
--- monitoring new versions in the log from `monitor` (usually default) branch.
---
--- # Rollback ~
---
--- To roll back after an unfortunate update:
--- - Get identifier of latest working state:
---     - Use |:DepsShowLog| to see update log, look for plugin's name, and copy
---       identifier listed as "State before:".
---     - See previously saved snapshot file for plugin's name and copy
---       identifier next to it.
--- - Freeze plugin at that state while monitoring appropriate branch.
---   Revert to previous shape of |FailwindDeps.add()| call to resume updating.
---
--- # Remove ~
---
--- - Make sure that target plugin is not registered in current session.
---   Usually it means removing corresponding |FailwindDeps.add()| call.
--- - Run |:DepsClean|. This will show confirmation buffer with a list of plugins to
---   be deleted from disk. Follow instructions at its top to finish cleaning.
---
--- Alternatively, manually delete plugin's directory from "pack/failwind" package.
---@tag FailwindDeps-overview

--- # Plugin specification ~
---
--- Each plugin dependency is managed based on its specification (a.k.a. "spec").
--- See |FailwindDeps-overview| for some examples.
---
--- Specification can be a single string which is inferred as:
--- - Plugin <name> if it doesn't contain "/".
--- - Plugin <source> otherwise.
---
--- Primarily, specification is a table with the following fields:
---
--- - <source> `(string|nil)` - field with URI of plugin source used during creation
---   or update. Can be anything allowed by `git clone`.
---   Default: `nil` to rely on source set up during install.
---   Notes:
---     - It is required for creating plugin, but can be omitted afterwards.
---     - As the most common case, URI of the format "user/repo" is transformed
---       into "https://github.com/user/repo".
---
--- - <name> `(string|nil)` - directory basename of where to put plugin source.
---   It is put in "pack/failwind/opt" subdirectory of `config.path.package`.
---   Default: basename of <source> if it is present, otherwise should be
---   provided explicitly.
---
--- - <checkout> `(string|nil)` - checkout target used to set state during update.
---   Can be anything supported by `git checkout` - branch, commit, tag, etc.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <monitor> `(string|nil)` - monitor branch used to track new changes from
---   different target than `checkout`. Should be a name of present Git branch.
---   Default: `nil` for default branch (usually "main" or "master").
---
--- - <depends> `(table|nil)` - array of plugin specifications (strings or tables)
---   to be added prior to the target.
---   Default: `nil` for no dependencies.
---
--- - <hooks> `(table|nil)` - table with callable hooks to call on certain events.
---   Possible hook names:
---     - <pre_install>   - before creating plugin directory.
---     - <post_install>  - after  creating plugin directory.
---     - <pre_checkout>  - before making change in existing plugin.
---     - <post_checkout> - after  making change in existing plugin.
---   Each hook is executed with the following table as an argument:
---     - <path> (`string`)   - absolute path to plugin's directory
---       (might not yet exist on disk).
---     - <source> (`string`) - resolved <source> from spec.
---     - <name> (`string`)   - resolved <name> from spec.
---   Default: `nil` for no hooks.
---@tag FailwindDeps-plugin-specification

--- # User commands ~
---
--- Note: Most commands have a Lua function alternative which they rely on.
--- Like |:DepsAdd| uses |FailwindDeps.add()|, etc.
---
---                                                                       *:DepsAdd*
--- `:DepsAdd user/repo` makes plugin from https://github.com/user/repo available
--- in the current session (also creates it, if it is not present).
--- `:DepsAdd name` adds already installed plugin `name` to current session.
--- Accepts only single string compatible with |FailwindDeps-plugin-specification|.
--- To add plugin in every session, put |FailwindDeps.add()| in |init.lua|.
---
---                                                                    *:DepsUpdate*
--- `:DepsUpdate` synchronizes plugins with their session specifications and
--- updates them with new changes from sources. It shows confirmation buffer in
--- a separate |tabpage| with information about an upcoming update to review
--- and (selectively) apply. See |FailwindDeps.update()| for more info.
---
--- `:DepsUpdate name` updates plugin `name`. Any number of names is allowed.
---
--- `:DepsUpdate!` and `:DepsUpdate! name` update without confirmation.
--- You can see what was done in the log file afterwards (|:DepsShowLog|).
---
---                                                             *:DepsUpdateOffline*
--- `:DepsUpdateOffline` is same as |:DepsUpdate| but doesn't download new updates
--- from sources. Useful to only synchronize plugin specification in code and
--- on disk without unnecessary downloads.
---
---                                                                   *:DepsShowLog*
--- `:DepsShowLog` opens log file to review.
---
---                                                                     *:DepsClean*
--- `:DepsClean` deletes plugins from disk not added to current session. It shows
--- confirmation buffer in a separate |tabpage| with information about an upcoming
--- deletes to review and (selectively) apply. See |FailwindDeps.clean()| for more info.
---
--- `:DepsClean!` deletes plugins without confirmation.
---
---                                                                  *:DepsSnapSave*
--- `:DepsSnapSave` creates snapshot file in default location (see |FailwindDeps.config|).
--- `:DepsSnapSave path` creates snapshot file at `path`.
---
---                                                                  *:DepsSnapLoad*
---
--- `:DepsSnapLoad` loads snapshot file from default location (see |FailwindDeps.config|).
--- `:DepsSnapLoad path` loads snapshot file at `path`.
---@tag FailwindDeps-commands

---@diagnostic disable:undefined-field
---@diagnostic disable:discard-returns
---@diagnostic disable:unused-local
---@diagnostic disable:cast-local-type
---@diagnostic disable:undefined-doc-name
---@diagnostic disable:luadoc-miss-type-name

-- Module definition ==========================================================
local FailwindDeps = {}
local H = {}

--- Module setup
---
--- Calling this function creates user commands described in |FailwindDeps-commands|.
---
---@param config table|nil Module config table. See |FailwindDeps.config|.
---
---@usage >lua
---   require('failwind.deps').setup() -- use default config
---   -- OR
---   require('failwind.deps').setup({}) -- replace {} with your config table
--- <
FailwindDeps.setup = function(config)
  -- Export module
  _G.FailwindDeps = FailwindDeps

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Create default highlighting
  H.create_default_hl()

  -- Create user commands
  H.create_user_commands()
end

--stylua: ignore
--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # Job ~
---
--- `config.job` defines how CLI jobs are run.
---
--- `job.n_threads` is a maximum number of parallel jobs used when needed.
--- Default: 80% of all available.
---
--- `job.timeout` is a duration (in ms) from job start until it is forced to stop.
--- Default: 30000.
---
--- # Paths ~
---
--- `config.path` defines main paths used in this module.
---
--- `path.package` is a string with path inside which "pack/failwind" package is stored
--- (see |FailwindDeps-overview|).
--- Default: "site" subdirectory of "data" standard path (see |stdpath()|).
---
--- `path.snapshot` is a string with default path for snapshot.
--- See |:DepsSnapSave| and |:DepsSnapLoad|.
--- Default: "failwind.deps-snap" file in "config" standard path (see |stdpath()|).
---
--- `path.log` is a string with path containing log of operations done by module.
--- In particular, it contains all changes done after making an update.
--- Default: "failwind.deps.log" file in "log" standard path (see |stdpath()|).
---
--- # Silent ~
---
--- `config.silent` is a boolean controlling whether to suppress non-error feedback.
--- Default: `false`.
FailwindDeps.config = {
  -- Parameters of CLI jobs
  job = {
    -- Number of parallel threads to use. Default: 80% of all available.
    n_threads = nil,

    -- Timeout (in ms) for each job before force quit
    timeout = 30000,
  },

  -- Paths describing where to store data
  path = {
    -- Directory for built-in package.
    -- All plugins are actually stored in 'pack/failwind' subdirectory.
    package = vim.fn.stdpath('data') .. '/site',

    -- Default file path for a snapshot
    snapshot = vim.fn.stdpath('config') .. '/failwind.deps-snap',

    -- Log file
    --minidoc_replace_start log = vim.fn.stdpath('log') .. '/failwind.deps.log'
    log = vim.fn.stdpath('log') .. '/failwind.deps.log',
    --minidoc_replace_end
  },

  -- Whether to disable showing non-error feedback
  silent = false,
}
--minidoc_afterlines_end

--- Add plugin to current session
---
--- - Process specification by expanding dependencies into single spec array.
--- - Ensure plugin is present on disk along with its dependencies by installing
---   (in parallel) absent ones:
---     - Execute `opts.hooks.pre_install`.
---     - Use `git clone` to clone plugin from its source URI into "pack/failwind/opt".
---     - Set state according to `opts.checkout`.
---     - Execute `opts.hooks.post_install`.
--- - Register spec(s) in current session.
--- - Make sure plugin(s) can be used in current session (see |:packadd|).
--- - If not during startup and is needed, source all "after/plugin/" scripts.
---
--- Notes:
--- - Presence of plugin is checked by its name which is the same as the name
---   of its directory inside "pack/failwind" package (see |FailwindDeps-overview|).
--- - To increase performance, this function only ensures presence on disk and
---   nothing else. In particular, it doesn't ensure `opts.checkout` state.
---   Use |FailwindDeps.update()| or |:DepsUpdateOffline| explicitly.
--- - Adding plugin several times updates its session specs.
---
---@param sp
