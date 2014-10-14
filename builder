#!/bin/sh
#
# fatal error. Print message then quit with exitval
err() {
	exitval=$1
	shift
	echo  "$*" 1>&2
	exit $exitval
}

pre()
{
	fakeroot="$( mktemp -d )" || err 1 "Cant't create fakeroot"
	DIR="$( mktemp -d )" || err 1 "Can't create fakeroot"
}

post()
{
	[ -d "${fakeroot}" ] && rm -rf ${fakeroot}
	[ -d "${DIR}" ] && rm -rf ${DIR}
}

usage()
{
	echo 1>&2 "usage: $0 [options]"
	echo 1>&2 ""
	echo 1>&2 " Options:"
	echo 1>&2 " -c path to conf"
	echo 1>&2 " -r path Path to repo"
	echo 1>&2 " -p prefix path for extracted deb (e.g: -p /usr/local)"
	echo 1>&2 ""
	exit 1
}

set_files()
{
	local _files _file _md5 _tmpfile
	_files=$( eval $find_files )

	for _file in ${_files}; do
		_md5=$( md5sum /${_file} |awk '{printf $1 }' )
		_tmpfile="${_file#$fakeroot}"
		_file=$( echo ${_tmpfile} |sed 's/\///' )
		files="${files:-}${files:+
}${_md5} ${_file}"
	done
}

set_dirs()
{
	local _dirs _dir
	_dirs=$( eval $find_dirs )
	for _dir in ${_dirs}; do
		if [ "${_dir}" = "$fakeroot" ]; then
			continue
		fi
		dirs="${dirs:-}${dirs:+
		} ${_dir#$fakeroot}/: y"
	done
}

set_flatsize()
{
	flatsize=$( eval $find_size | awk 'BEGIN {s=0} {s+=$1} END {print s}' )
}


### MAIN ###
unset conf repo

while getopts "c:r:p:" opt; do
	case "$opt" in
		c) conf="$OPTARG" ;;
		r) repo="$OPTARG" ;;
		p) newroot="${OPTARG}" ;;
		d) set -x ;;
		*) usage ;;
	esac
	shift $(($OPTIND - 1))
done

[ -z "${conf}" -o -z "${repo}" ] && usage

pkgdir="$( dirname $0 )" # XXX

if [ ! -d "$repo" ]; then
	err 1 "Please create $repo dir"
fi

set -e
pre
trap "post" HUP INT ABRT BUS TERM EXIT

# init empty variable for manifest
Package=
Version=
Architecture=
Maintainer=
Depends=
Section=
Priority=
Description=

# read defaults
. ${pkgdir}/defaults.conf

# overlap per-project params
. $conf

_fakeroot="$fakeroot"
[ -n "${newroot}" ] && root="${newroot}"

find_files="find ${_fakeroot}${root}${SRCDIR} -type f"
find_dirs="find ${_fakeroot}${root}${SRCDIR} -type d"
find_size="find ${_fakeroot}${root}${SRCDIR} -type f -exec stat -c %s {} \+"

[ -z "${SRCDIR}" -o ! -d "${SRCDIR}" ] && err 1 "No such source: $SRCDIR"
SRC_DIRNAME=$( dirname ${SRCDIR} )
[ -n "${root}" ] && SRC_DIRNAME="${root}/${SRC_DIRNAME}"
mkdir -p "${fakeroot}/${SRC_DIRNAME}"
cp -a ${SRCDIR} ${fakeroot}/${SRC_DIRNAME}

files=
dirs=

set_files
#set_dirs
set_flatsize

if [ -f "${SRCDIR}/.git/config" ]; then
	cd ${SRCDIR}
	[ Version=$( git log -n1 |/usr/bin/awk '/commit /{print $2}' |head -c 8 )
fi

[ -z "${Version}" ] && Version="0.1"

cat > ${DIR}/control <<EOF
Package: ${Package}
Version: ${Version}
Architecture: ${Architecture}
Maintainer: ${Maintainer}
Installed-Size: ${flatsize}
Depends: ${Depends}
Section: ${Section}
Priority: ${Priority}
Description: ${Description}
EOF

echo "${files}" > ${DIR}/md5sums

cd ${DIR}
tar zcvf control.tar.gz control md5sums
rm -f control md5sums

cd ${fakeroot}
tar cfz ${DIR}/data.tar.gz *

rm -rf ${fakeroot}

echo "2.0" > ${DIR}/debian-binary
cd ${DIR}
ar rcv ${Package}-${Version}.deb debian-binary control.tar.gz data.tar.gz

mv ${Package}-${Version}.deb ${repo}/
file -s ${repo}/${Package}-${Version}.deb
