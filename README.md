#Automatic RPM/DEB builder

We write system for building LUA rockspec modules into `*.RPM's` and `*.DEB's`. It's fork of luarocks with added c99 and binary packing:

## On rockspecs

Rockspec is a set of fields, that defines a package in a way, like python's `setup.py`, perl's `Makefile.PL` or RPM's 'RPM.spec'. For example we'll take [http-scm-1.rockspec][http_rspc]:

```lua
package = 'http'
version = 'scm-1'
source = {
    url = 'git://github.com/tarantool/http.git',
    branch = 'master',
}
description = {
    summary = "Tarantool module for HTTP client/server.",
    homepage = 'https://github.com/tarantool/http/',
    license = 'BSD',
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',

    modules = {
        ['box.http.lib'] = 'src/lib.c',
        ['box.http.client'] = 'src/client.lua',
        ['box.http.server'] = 'src/server.lua',
        ['box.http.mime_types'] = 'src/mime_types.lua',
        ['box.http.codes'] = 'src/codes.lua',
    },
    c99 = true,
}
```

Fields:

* `package` - name of package, without `tarantool-` prefix. (MANDATORY)
* `version` - version of your package. It is `<package_version>-<revision>`, where `package_version` may be anything, but revision is a natural number. `package_version` may be `scm`(reduction of 'Source Code Management') - used for bleeding edge rockspecs (we'll talk about types of rockspecs later) (MANDATORY)
* `source` - must be table with fields `url` and, optionally, `branch` (MANDATORY):
    * `source.url` - is path to VCS repo or `.tar.*/.zip` archives. (MANDATORY)
    * `source.branch` - is a branch to checkout (for VCS).
    * `source.tag` - is a tag to checkout (for VCS).
    * `source.md5` - is a md5 of archive.
    * `source.file` - is a file name to download archive to.
    * `source.dir` - is the name for directory to unpack archive to.
* `description` - must be table with listed fields (MANDATORY):
    * `summary` - short, one-line description of project
    * `homepage` - home-page of this project
    * `license` - license under which product is distributed
    * `maintainer` - one, who wrote this spec
    * `details` - a detailed description of module
* `build` - must be table with listed fields (MANDATORY):
    * `type` - currently supported only `builtin` OR `make`, `command` or `none` with `install` field.
    * Other fields are explained later
* `dependencies`, `external_dependencies` - read about them on luarocks [site](http://www.luarocks.org/en/Rockspec_format)

For `builtin` type:

* `c99` - module must be built with support of `--std=c99`
* `modules` - must be table with mapping module->source file(s)
    * semantics of module - `['box.http.lib']` where dots means subcatalog
    * value of mapping is:
        * string with path to Lua file in root of package.
        * string with path to C file to compile
        * table with paths to C files.
        * table with following fields:
            * `sources` - table of string - pathname of C sources
            * `libraries` - external libraries to be linked with
            * `defines` - table of C defines. `{"FOO=bar", "USE_BLA"}`
            * `incdirs` - additional dir's where to search headers in
            * `libdirs` - additional dir's where to search for libraries

For `make` type:

* `makefile` - makefile to be used. Default is 'Makefile'
* `build_target` - target for building. Default is ""
* `install_pass` - skip target for installing. Default is `true`, but MUST be `false` in order for packaging works just fine.
* `build_variables` - assignments to be passed to make during the build pass. Default is {}. Expected 'CC', 'CFLAGS' and 'LIBFLAGS'
* `install` - table, that have keys `lua` and `lib`, that defines what it must install and where:
    * `lua` - keys are like in `semantics of modules`(of `builtin` builder), values are paths for libs, written on Lua
    * `lib` - keys are like in `semantics of modules`(of `builtin` builder), values are paths for libs, written on C

For example:

```lua 
build = {
    type = "make",
    makefile = "Makefile",
    build_target = "build_zmq_poller",
    install_pass = false,
    install = {
        lua = {
            ['zmq.threads'] = "src/threads.lua",
        }
        lib = {
            ['zmq.poller'] = "poller.so"
        }
    }
}
```

For `command` type:

* `build_command` - command to run build the package
* `install` - explained in `make` section

For `none` type:

* `install` - explained in `make` section

Composer of rockspec must stick to some rules:

* If module not builded with `builtin` builder, then it MUST install files via `install` field, nor `install_command` or `install_target`.

TODO: other rules.

## Build system

* Currently supported VCS: `git` only.
* Currently supported OS : DEB/RPM based linux'es.
* Currently not supported dependencies in RPM/DEB.
* It depends on `wget` and `md5`


### Installing

Simply clone `bigbe92/luarocks` at `github`, modify `luarocks/src/luarocks/site_config.lua` (explained later, but you may use standard settings), change dir to `luarocks/src/bin` and start is with `./luarocks` command.
For building lua module you'll need simply `./luarocks build <rockspec_path_or_name_in_repo> --build-rpm` or `--build-deb`.

For `--build-rpm` you'll need `rpmbuild` and for `--build-deb` you'll need `fakeroot` and `alien`. It'll check deps on start.

### How it works

It generates RPM spec, with all builded files. Takes all fields from rockspec, gets all installed files, and composes `rpm.spec`, then builds it with `rpmbuild`. If you need to build deb package, than it uses `fakeroot alien` for converting it's packages from RPM to DEB, but `lib` paths are modified.
It uses temporary directory for luarocks repo (`/tmp/luarocks_build_dir` by default). You may simply delete it after building module.

### Configuration

There's file `luarocks/src/luarocks/site_config.lua` - it defines global configuration for building modules. There are some fields, that it supports:

* `LUA_INCDIR`, `LUA_LIBDIR`, `LUA_BINDIR` - path for includes for Tarantool headers, path for includes of Tarantool libraries and path for Tarantool binary
* `LUAROCKS_ROCKS_TREE` - path for temporary dir, where rocks are installed.
* `LUAROCKS_UNAME_S`, `LUAROCKS_UNAME_M` - name and arch of OS where module is building
* `LUAROCKS_EXTERNAL_DEPS_SUBDIR`, `LUAROCKS_RUNTIME_EXTERNAL_DEPS_SUBDIR` - paths where to search for `external_dependencies`

### Tarantool repo

Our repository is located at [github](http://github.com/tarantool/rocks/tree/gh-pages) at gh-pages branch.
Currently we have one rockspec - [`http-scm-1.rockspec`][http_rspc], but if you'll create another you may submit another one.
If you'll submit your rockspec, don't forget about running `luarocks-admin make_manifest ./` in the root of repo and, then, zip files:
`zip manifest-5.1.zip manifest-5.1` and `zip manifest-5.2.zip manifest-5.2` and then, reconfigure buildbot for building all modules for latest tarantool.

[http_rspc]: https://github.com/tarantool/rocks/blob/gh-pages/http-scm-1.rockspec
