#!/bin/sh
#
# Copyright 2005 Timo Hirvonen
#
# This file is licensed under the GPLv2.

# locals {{{

# pkg_check_modules, app_config
module_names=""

# --enable-$NAME flags
# $NAME must contain only [a-z0-9-] characters
enable_flags=""

# put config values to config.h and config.mk
enable_use_config_h_val=yes
enable_use_config_mk_val=yes

# option flags
opt_flags=""

# For each --enable-$NAME there are
#   enable_value_$NAME
#   enable_desc_$NAME
#   enable_var_$NAME
# variables and check_$NAME function

# for each $config_vars there are
#   cv_value_$NAME
#   cv_desc_$NAME
#   cv_type_$NAME
config_vars=""

# config.mk variable names
mk_env_vars=""

# these are environment variables
install_dir_vars="prefix exec_prefix bindir sbindir libexecdir datadir sysconfdir sharedstatedir localstatedir libdir includedir infodir mandir"
set_install_dir_vars=""

checks=""

CROSS=

did_run()
{
	set_var did_run_$1 yes
}

before()
{
	if test "$(get_var did_run_$1)" = yes
	then
		echo
		echo "Bug in the configure script!"
		echo "Function $2 was called after $1."
		exit 1
	fi
}

after()
{
	if test "$(get_var did_run_$1)" != yes
	then
		echo
		echo "Bug in the configure script!"
		echo "Function $2 was called before $1."
		exit 1
	fi
}

get_dir_val()
{
	local val

	val=$(get_var $1)
	if test -z "$val"
	then
		echo "$2"
	else
		echo "$val"
	fi
}

show_help()
{
	local _bindir _sbindir _libexecdir _datadir _sysconfdir _sharedstatedir _localstatedir _libdir _includedir _infodir _mandir

	_bindir=$(get_dir_val bindir EPREFIX/bin)
	_sbindir=$(get_dir_val sbindir EPREFIX/sbin)
	_libexecdir=$(get_dir_val libexecdir EPREFIX/libexec)
	_datadir=$(get_dir_val datadir PREFIX/share)
	_sysconfdir=$(get_dir_val sysconfdir PREFIX/etc)
	_sharedstatedir=$(get_dir_val sharedstatedir PREFIX/com)
	_localstatedir=$(get_dir_val localstatedir PREFIX/var)
	_libdir=$(get_dir_val libdir EPREFIX/lib)
	_includedir=$(get_dir_val includedir PREFIX/include)
	_infodir=$(get_dir_val infodir PREFIX/info)
	_mandir=$(get_dir_val mandir PREFIX/share/man)

	cat <<EOT
Usage: ./configure [options] [VARIABLE=VALUE]...

Installation directories:
  --prefix=PREFIX         install architecture-independent files in PREFIX
                          [/usr/local]
  --exec-prefix=EPREFIX   install architecture-dependent files in EPREFIX
                          [PREFIX]

Cross compiling:
  --cross=MACHINE        cross-compile []

Fine tuning of the installation directories:
  --bindir=DIR           user executables [$_bindir]
  --sbindir=DIR          system admin executables [$_sbindir]
  --libexecdir=DIR       program executables [$_libexecdir]
  --datadir=DIR          read-only architecture-independent data [$_datadir]
  --sysconfdir=DIR       read-only single-machine data [$_sysconfdir]
  --sharedstatedir=DIR   modifiable architecture-independent data [$_sharedstatedir]
  --localstatedir=DIR    modifiable single-machine data [$_localstatedir]
  --libdir=DIR           object code libraries [$_libdir]
  --includedir=DIR       C header files [$_includedir]
  --infodir=DIR          info documentation [$_infodir]
  --mandir=DIR           man documentation [$_mandir]

Optional Features:
  --disable-FEATURE       do not include FEATURE (same as --enable-FEATURE=no)
  --enable-FEATURE[=ARG]  include FEATURE (ARG=yes|no|auto) [ARG=yes]
EOT
	local i tmp text=
	for i in $enable_flags
	do
		strpad "--enable-$(echo $i | sed 's/_/-/g')" 22
		text="${text}  $strpad_ret  $(get_var enable_desc_${i}) [$(get_var enable_value_${i})]\n"
	done
	if test -n "$opt_flags"
	then
		text="${text}\n"
		for i in $opt_flags
		do
			tmp=$(get_var flag_argdesc_${i})
			strpad "--$(echo $i | sed 's/_/-/g')${tmp}" 22
			tmp=$(get_var flag_desc_${i})
			text="${text}  $strpad_ret  ${tmp}\n"
		done
	fi
	echo -ne "$text\nSome influential environment variables:\n  CC CFLAGS LD LDFLAGS SOFLAGS\n  CXX CXXFLAGS CXXLD CXXLDFLAGS\n"
	exit 0
}

is_enable_flag()
{
	list_contains "$enable_flags" "$1"
}

handle_enable()
{
	local flag val

	flag="$1"
	val="$2"
	is_enable_flag "$flag" || die "invalid option --enable-$key"
	case $val in
		yes|no|auto)
			set_var enable_value_${flag} $val
			;;
		*)
			die "invalid argument for --enable-${flag}"
			;;
	esac
}

reset_vars()
{
	local name

	for name in $install_dir_vars PACKAGE VERSION PACKAGE_NAME PACKAGE_BUGREPORT
	do
		set_var $name ''
	done
}

set_unset_install_dir_vars()
{
	var_default prefix "/usr/local"
	var_default exec_prefix "$prefix"
	var_default bindir "$exec_prefix/bin"
	var_default sbindir "$exec_prefix/sbin"
	var_default libexecdir "$exec_prefix/libexec"
	var_default datadir "$prefix/share"
	var_default sysconfdir "$prefix/etc"
	var_default sharedstatedir "$prefix/com"
	var_default localstatedir "$prefix/var"
	var_default libdir "$exec_prefix/lib"
	var_default includedir "$prefix/include"
	var_default infodir "$prefix/info"
	var_default mandir "$prefix/share/man"
}

set_makefile_variables()
{
	local flag i

	for flag in $enable_flags
	do
		local var=$(get_var enable_var_${flag})
		if test -n "$var" && test "$(get_var enable_config_mk_${flag})" = yes
		then
			local v
			if test "$(get_var enable_value_${flag})" = yes
			then
				v=y
			else
				v=n
			fi
			makefile_var $var $v
		fi
	done

	for i in $module_names
	do
		makefile_env_vars ${i}_CFLAGS ${i}_LIBS
	done

	makefile_env_vars $install_dir_vars
}

set_config_h_variables()
{
	local flag name

	config_str PACKAGE "$PACKAGE" "package name (short)"
	config_str VERSION "$VERSION" "packege version"
	test -n "$PACKAGE_NAME" && config_str PACKAGE_NAME "$PACKAGE_NAME" "package name (full)"
	test -n "$PACKAGE_BUGREPORT" && config_str PACKAGE_BUGREPORT "$PACKAGE_BUGREPORT" "address where bug reports should be sent"

	for flag in $enable_flags
	do
		local var=$(get_var enable_var_${flag})
		if test -n "$var" && test "$(get_var enable_config_h_${flag})" = yes
		then
			config_var "${var}" "$(get_var enable_value_${flag})" "$(get_var enable_desc_${flag})" bool
		fi
	done

	for name in $install_dir_vars
	do
		config_str $(echo $name | to_upper) "$(get_var $name)"
	done
}

# }}}

parse_command_line()
{
	local kv key var val
	local name

	for name in PACKAGE VERSION
	do
		test -z "$(get_var $name)" && die "$name must be defined in 'configure'"
	done

	add_flag help no show_help "show this help and exit"

	# parse flags (--*)
	while test $# -gt 0
	do
		case $1 in
			--enable-*)
				kv=${1##--enable-}
				key=${kv%%=*}
				if test "$key" = "$kv"
				then
					# '--enable-foo'
					val=yes
				else
					# '--enable-foo=bar'
					val=${kv##*=}
				fi
				handle_enable "$(echo $key | sed 's/-/_/g')" "$val"
				;;
			--disable-*)
				key=${1##--disable-}
				handle_enable "$(echo $key | sed 's/-/_/g')" "no"
				;;
			--prefix=*|--exec-prefix=*|--bindir=*|--sbindir=*|--libexecdir=*|--datadir=*|--sysconfdir=*|--sharedstatedir=*|--localstatedir=*|--libdir=*|--includedir=*|--infodir=*|--mandir=*)
				kv=${1##--}
				key=${kv%%=*}
				val=${kv##*=}
				var=$(echo $key | sed 's/-/_/g')
				set_var ${var} "$val"
				set_install_dir_vars="${set_install_dir_vars} ${var}"
				;;
			--cross=*)
				CROSS=${1##--cross=}
				;;
			--)
				shift
				break
				;;
			--*)
				local name found f
				kv=${1##--}
				key=${kv%%=*}
				name="$(echo $key | sed 's/-/_/g')"
				found=false
				for f in $opt_flags
				do
					if test "$f" = "$name"
					then
						if test "$key" = "$kv"
						then
							# '--foo'
							test "$(get_var flag_hasarg_${name})" = yes && die "--${key} requires an argument (--${key}$(get_var flag_argdesc_${name}))"
							$(get_var flag_func_${name}) ${key}
						else
							# '--foo=bar'
							test "$(get_var flag_hasarg_${name})" = no && die "--${key} must not have an argument"
							$(get_var flag_func_${name}) ${key} "${kv##*=}"
						fi
						found=true
						break
					fi
				done
				$found || die "unrecognized option \`$1'"
				;;
			*)
				break
				;;
		esac
		shift
	done

	while test $# -gt 0
	do
		case $1 in
			*=*)
				key=${1%%=*}
				val=${1#*=}
				set_var $key "$val"
				;;
			*)
				die "unrecognized argument \`$1'"
				;;
		esac
		shift
	done

	set_unset_install_dir_vars
	did_run parse_command_line

	top_srcdir=$(follow_links $srcdir)
	test -z "$top_srcdir" && exit 1
	top_builddir=$(follow_links $PWD)
	test -z "$top_builddir" && exit 1
	makefile_env_vars PACKAGE VERSION top_builddir top_srcdir scriptdir

	for i in PACKAGE VERSION PACKAGE_NAME PACKAGE_BUGREPORT top_builddir top_srcdir $install_dir_vars
	do
		export $i
	done
}

run_checks()
{
	local check flag

	after parse_command_line run_checks

	trap 'rm -f .tmp-*' 0 1 2 3 13 15
	for check in $checks
	do
		$check || die -e "\nconfigure failed."
	done
	for flag in $enable_flags
	do
		local val=$(get_var enable_value_${flag})
		if test "$val" != no
		then
			if ! is_function check_${flag}
			then
# 				test "$val" = auto && die ""
				continue
			fi

			if check_${flag}
			then
				# check successful
				set_var enable_value_${flag} yes
			else
				# check failed
				if test "$val" = yes
				then
					die "configure failed."
				else
					# auto
					set_var enable_value_${flag} no
				fi
			fi
		fi
	done

	# .distclean has to be removed before calling generated_file()
	# but not before configure has succeeded
	rm -f .distclean
	did_run run_checks
}

var_print()
{
	strpad "$1:" 20
	echo "${strpad_ret} $(get_var $1)"
}

config_var()
{
	after parse_command_line config_var
	before generate_config_h config_var

	config_vars="$config_vars $1"
	set_var cv_value_$1 "$2"
	set_var cv_desc_$1 "$3"
	set_var cv_type_$1 "$4"
}

update_file()
{
	local old new

	new="$1"
	old="$2"
	if test -e "$old"
	then
		cmp "$old" "$new" 2>/dev/null 1>&2 && return 0
	fi
	mv -f "$new" "$old"
}

generate_config_h()
{
	local tmp i

	after run_checks generate_config_h

	set_config_h_variables
	echo "Generating config.h"
	tmp=$(tmp_file config.h)
	output_file $tmp
	out "#ifndef _CONFIG_H"
	out "#define _CONFIG_H"
	for i in $config_vars
	do
		local v d t
		v=$(get_var cv_value_${i})
		d=$(get_var cv_desc_${i})
		t=$(get_var cv_type_${i})
		out
		test -n "$d" && out "/* $d */"
		case $t in
			bool)
				case $v in
					no)
						out "/* #define $i */"
						;;
					yes)
						out "#define $i 1"
						;;
				esac
				;;
			int)
				out "#define $i $v"
				;;
			str)
				out "#define $i \"$v\""
				;;
		esac
	done
	out
	out "#endif"
	update_file $tmp config.h
	did_run generate_config_h
}

generate_config_mk()
{
	local i s c tmp

	after run_checks generate_config_mk

	set_makefile_variables
	echo "Generating config.mk"
	tmp=$(tmp_file config.mk)
	output_file $tmp
	out '# run "make help" for usage information'
	out
	for i in $mk_env_vars
	do
		s="export ${i}"
		c=$((24 - ${#s}))
		while test $c -gt 0
		do
			s="${s} "
			c=$(($c - 1))
		done
		out "${s} := $(get_var $i)"
	done
	out
	out 'include $(scriptdir)/main.mk'
	update_file $tmp config.mk
	did_run generate_config_mk
}

reset_vars
