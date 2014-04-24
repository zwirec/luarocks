module('luarocks.rpm', package.seeall)

local repos = require('luarocks.repos')
local manif = require('luarocks.manif')
local path = require('luarocks.path')
local cfg = require('luarocks.cfg')
local dir = require('luarocks.dir')
local fs = require('luarocks.fs')

local buildrootpath = [[/tmp/luarocks_build_dir/usr]]

local rpm_mandatory = [[
Name: __prefix__name
Version: __version
Release: __release
Summary: __summary

Group: Development/Libraries
BuildRoot: __root
]]

local rpm_license = [[
License: __license
]]

local rpm_url = [[
URL: __url
]]

local rpm_description = [[
%%description
__description
]]

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

function string:replace_format(dict)
    local ans = self
    for key, value in pairs(dict) do
        ans = ans:gsub('__'..key, value)
    end
    return ans
end

function configure_header(rockspec, prefix)
    cfg = {}
    cfg.prefix = prefix or 'tarantool-'
    cfg.name = rockspec.package
    cfg.version = rockspec.version
    if cfg.version:find('^scm') == 'scm' then
        if rockspec.source.url:find('^git') then
            cfg.version = io.popen('git describe', 'r'):read('*l')
            cfg.release = cfg.version:split('-')[2]
            cfg.version = cfg.version:split('-')[1]
        else
            error('This SCM doesn\'t have a support')
        end
    else
        cfg.release = cfg.version:split('-')[2]
        cfg.version = cfg.version:split('-')[1]
    end
    cfg.summary = rockspec.description.summary
    cfg.description = rockspec.description.detailed
    cfg.license = rockspec.description.license
    cfg.url = rockspec.description.homepage
    cfg.root = buildrootpath
    local rpm_spec = rpm_mandatory:replace_format(cfg)
    if cfg.url then
        rpm_spec = rpm_spec .. rpm_url:replace_format{url = cfg.url}
    end
    if cfg.license then
        rpm_spec = rpm_spec .. rpm_license:replace_format{license = cfg.license}
    end
    if cfg.description then
        rpm_spec = rpm_spec .. rpm_description:replace_format{description = cfg.description}
    end
    return rpm_spec
end


local rpm_file_prefix = {
    {buildrootpath..[[/share]], [[%%{_datadir}]]},
    {buildrootpath..[[/lib]]  , [[%%{_libdir}]]}
}

local function rpm_fix_prefixes(table_val)
    for k, v in pairs(table_val) do
        prev = v
        for _, substr in pairs(rpm_file_prefix) do
            v = v:gsub(substr[1], substr[2])
        end
        table_val[k] = {prev, v}
    end
end

local function get_inter_paths(table_val)
    local paths = {}
    for _, v in pairs(table_val) do
        local cont_flag = true
        local parent_dir = dir.dir_name(v[2])
        while (parent_dir ~= [[%{_datadir}]] and parent_dir ~= [[%{_libdir}]] and cont_flag) do
            for _, pth in pairs(paths) do
                if pth == parent_dir then
                    cont_flag = false
                    break
                end
            end
            if cont_flag then table.insert(paths, parent_dir) end
            parent_dir = dir.dir_name(parent_dir)
        end
    end
    return paths
end

function generate_install(list)
    local install_directive = [[%install
]]
    local inter_paths = get_inter_paths(list)
    table.sort(inter_paths)
    for _, v in pairs(inter_paths) do
        install_directive = install_directive .. [[mkdir -p %{buildroot}]]
        .. v .. '\n'
    end
    for _, v in pairs(list) do
        install_directive = install_directive .. (
        'if [ ! -f %{buildroot}' .. v[2] .. ' ]; then\n' ..
        [[install -p ]] .. v[1] .. ' %{buildroot}' .. v[2] .. '\nfi\n')
    end
    return install_directive
end

function generate_files(list)
    local files_directive = [[
%files
%defattr(-, root, root)
]]
    local inter_paths = get_inter_paths(list)
    table.sort(inter_paths)
    for _, v in pairs(inter_paths) do
        files_directive = files_directive .. [[%dir "/]] .. v .. '"\n'
    end
    for _, v in pairs(list) do
        files_directive = files_directive ..'"/'.. v[2] .. '"\n'
    end
    return files_directive
end

function configure_files(name, version)
    local file_list = {}

    local function deploy_file_tree(file_tree, path_fn, deploy_dir)
        local source_dir = path_fn(name, version)
        local function __temp(parent_path, parent_module, file)
            local target = dir.path(deploy_dir, parent_path, file)
            table.insert(file_list, target)
            return true
        end
        return repos.recurse_rock_manifest_tree(file_tree, __temp)
    end
    local rock_manifest = manif.load_rock_manifest(name, version)

    if rock_manifest.lua then deploy_file_tree(rock_manifest.lua, path.lua_dir, cfg.deploy_lua_dir) end
    if rock_manifest.lib then deploy_file_tree(rock_manifest.lib, path.lib_dir, cfg.deploy_lib_dir) end
    rpm_fix_prefixes(file_list)
    return generate_install(file_list) .. '\n' .. generate_files(file_list)
end
