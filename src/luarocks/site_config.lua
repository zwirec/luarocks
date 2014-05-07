module("luarocks.site_config")

LUAROCKS_PREFIX=[[/tmp/lrcks-tmp]]
LUA_INCDIR=[[/usr/include/tarantool/]]
LUA_LIBDIR=[[/usr/lib]]
LUA_BINDIR=[[/usr/bin]]
LUAROCKS_SYSCONFDIR=[[/tmp/luarocks-build-dir/usr/etc/luarocks]]
LUAROCKS_ROCKS_TREE=[[/tmp/luarocks_build_dir/usr]]
LUAROCKS_ROCKS_SUBDIR=[[/lib/luarocks/rocks]]
LUAROCKS_UNAME_S=[[Linux]]
LUAROCKS_UNAME_M=[[x86_64]]
LUAROCKS_DOWNLOADER=[[wget]]
LUAROCKS_MD5CHECKER=[[md5sum]]

LUAROCKS_EXTERNAL_DEPS_SUBDIRS = {
    bin = "bin",
    lib = {
        "lib",
        [[lib/x86_64-linux-gnu]]
    },
    include="include"
}
LUAROCKS_RUNTIME_EXTERNAL_DEPS_SUBDIRS = {
    bin = "bin",
    lib = {
        "lib",
        [[lib/x86_64-linux-gnu]]
    },
    include = "include"
}

TARANTOOL_BIN_NAME=[[tarantool]]
TARANTOOL_VERSION =[[1.6]]
