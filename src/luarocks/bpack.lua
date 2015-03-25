module('luarocks.bpack', package.seeall)

local fetch = require('luarocks.fetch')
local repos = require('luarocks.repos')
local manif = require('luarocks.manif')
local path = require('luarocks.path')
local cfg = require('luarocks.cfg')
local dir = require('luarocks.dir')
local fs = require('luarocks.fs')

local buildrootpath = cfg.site_config.LUAROCKS_ROCKS_TREE

local rpm_mandatory = [[
Name: __prefix__name
Version: __version
Release: __release
Summary: __summary

Group: Development/Libraries
BuildRoot: __root
BuildArch: __arch
License: __license
URL: __url

%description
__description
]]

local rpm_file_prefix = {
    {buildrootpath..[[/share]], [[%%{_datadir}]]},
    {buildrootpath..[[/lib]]  , [[%%{_libdir}]]}
}

local function string_split(self, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

local function string_replace_format(self, _dict)
    local ans = self
    for key, value in pairs(_dict) do
        ans = ans:gsub('__'..key, value)
    end
    return ans
end

local function get_git_version(rockspec)
    local ok, source_dir, errcode = fetch.fetch_sources(rockspec, true)
    if not ok then
        error('Cannot fetch GIT repo: '.. errcode)
    end
    local version = io.popen(
        'cd '..dir.path(source_dir, ok)..'&& git describe --tags', 'r'):read('*l')
    os.execute('rm -rf '..source_dir)
    return version
end

local function get_arch()
    local f = io.popen('rpmbuild --showrc | grep _build_arch', 'r'):read('*l')
    local b = string_split(f, '%s')
    return b[3]
end


local function get_arch_dep(_cfg)
    local arch_dep = false
    for k, v in pairs(_cfg.file_list) do
        if v[1]:match('%.so') ~= nil then
            arch_dep = true
            break
        end
    end
    if arch_dep then
        _cfg.arch = get_arch()
    else
        _cfg.arch = 'noarch'
    end
    return _cfg.arch
end

-- configure header
function configure_header(rockspec, prefix, _cfg)
    _cfg.prefix = prefix or 'tarantool-'
    _cfg.name = rockspec.package
    local version = rockspec.version
    local tmp = version:find('^scm')
    if tmp == 1 then
        if rockspec.source.url:find('^git') then
            version = get_git_version(rockspec)
            _cfg.version = string_split(version, '-')[1]
            _cfg.release = string_split(version, '-')[2]
            if not _cfg.release then
                _cfg.release = '0'
            end
        else
            error('This SCM doesn\'t have a support')
        end
    else
        _cfg.version = string_split(version, '-')[1]
        _cfg.release = string_split(version, '-')[2]
    end
    _cfg.summary = rockspec.description.summary
    _cfg.description = rockspec.description.detailed
    _cfg.license = rockspec.description.license
    _cfg.url = rockspec.description.homepage
    _cfg.root = buildrootpath
    get_arch_dep(_cfg)
end

local function generate_header(_cfg)
    _cfg.rpm_header = string_replace_format(rpm_mandatory, _cfg)
    return _cfg.rpm_header
end

local function get_rpm_name(_cfg)
    local path = '__prefix__name-__version-__release.__arch.rpm'
    return string_replace_format(path, {
        prefix = _cfg.prefix,
        name = _cfg.name,
        arch = _cfg.arch, --  get_arch(),
        version = _cfg.version,
        release = _cfg.release,
    })
end

local function rpm_fix_prefixes(_cfg)
    for k, v in pairs(_cfg.file_list) do
        prev = v
        for _, substr in pairs(rpm_file_prefix) do
            v = v:gsub(substr[1], substr[2])
        end
        _cfg.file_list[k] = {prev, v}
    end
    return _cfg.file_list
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
    table.sort(paths)
    return paths
end

local function generate_install(_cfg)
    local install_directive = '%install\n'
    for _, v in pairs(_cfg.inter_paths) do
        install_directive = install_directive .. [[mkdir -p %{buildroot}]] .. v .. '\n'
    end
    for _, v in pairs(_cfg.file_list) do
        install_directive = install_directive .. (
        'if [ ! -f %{buildroot}' .. v[2] .. ' ]; then\n' ..
        '\tinstall -p ' .. v[1] .. ' %{buildroot}' .. v[2] .. '\nfi\n')
    end
    _cfg.rpm_install_directive = install_directive
    return _cfg.rpm_install_directive
end

local function generate_files(_cfg)
    local files_directive = '\n'..[[%files]]..'\n'..[[%defattr(-, root, root)]]..'\n'
    for _, v in pairs(_cfg.inter_paths) do
        files_directive = files_directive .. [[%dir "/]] .. v .. '"\n'
    end
    for _, v in pairs(_cfg.file_list) do
        files_directive = files_directive ..'"/'.. v[2] .. '"\n'
    end
    _cfg.rpm_files_directive = files_directive
    return _cfg.rpm_files_directive
end

-- configure_files
function configure_files(name, version, _cfg)
    _cfg.file_list = {}

    local function deploy_file_tree(file_tree, path_fn, deploy_dir)
        local source_dir = path_fn(name, version)
        local function __temp(parent_path, parent_module, file)
            local target = dir.path(deploy_dir, parent_path, file)
            table.insert(_cfg.file_list, target)
            return true
        end
        return repos.recurse_rock_manifest_tree(file_tree, __temp)
    end
    local rock_manifest = manif.load_rock_manifest(name, version)

    if rock_manifest.lua then deploy_file_tree(rock_manifest.lua, path.lua_dir, cfg.deploy_lua_dir) end
    if rock_manifest.lib then deploy_file_tree(rock_manifest.lib, path.lib_dir, cfg.deploy_lib_dir) end

    _cfg.file_list = rpm_fix_prefixes(_cfg)
    _cfg.inter_paths = get_inter_paths(_cfg.file_list)

    return _cfg
end

-- dump
function rpm_spec_generate(_cfg)
    generate_header(_cfg)
    generate_install(_cfg)
    generate_files(_cfg)
    _cfg.rpm_spec_name = _cfg.name .. '-' .. _cfg.version .. '.rpm.spec'
    local f = io.open(_cfg.rpm_spec_name, 'w')
    f:write(_cfg.rpm_header .. _cfg.rpm_install_directive .. _cfg.rpm_files_directive)
    f:close()
end

-- create_rpm
function package_build(_cfg, deb_package)
    local flags = [[ --define='_build_name_fmt %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm']] ..
    [[ --define='_rpmdir ./']] ..
    [[ --define='_builddir ./temp_builddir']]
    if deb_package then
        flags = flags .. [[ --define='_libdir /usr/lib']]
    end
    os.execute('rpmbuild -bb ' .. _cfg.rpm_spec_name .. flags)
    os.execute('rm -rf ./temp_builddir')
    if deb_package then
        os.execute('fakeroot alien --to-deb '..get_rpm_name(_cfg))
        os.execute('rm -rf '..get_rpm_name(_cfg))
    end
end

function check_prerequisites(flags)
    if flags["build-rpm"] and flags["build-deb"] then
        if flags["pack-binary-rock"] then
            error("Can't use --pack-binary-rock and --build-rpm/--build-deb")
        end
        error("Can't have both --build-rpm and --build-deb simultaniously")
    end
    if flags["build-rpm"] or flags["build-deb"] then
        -- rpmbuild
        if not os.execute('rpmbuild --version > /dev/null') then
            error('`Rpmbuild` needed for building of RPM/DEB packages')
        end
    end
    if flags["build-deb"] then
        -- fakeroot
        if not os.execute('fakeroot --version > /dev/null') then
            error('`Fakeroot` needed for building of DEB packages')
        end
        -- alien
        if not os.execute('alien --version > /dev/null') then
            error('`Alien` needed for build DEB packages')
        end
    end
end
