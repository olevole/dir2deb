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
	echo 1>&2 " -j jailed/chroot environment. To create hier from /, do not inlcude folder name in prefix path"
	echo 1>&2 " -r path Path to repo"
	echo 1>&2 " -p prefix path for extracted deb (e.g: -p /usr/local)"
	echo 1>&2 " -d trace command for debug"
	echo 1>&2 " -s path to SRC_DIR "
	echo 1>&2 " -v overwrite version "
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
unset conf repo chroot

chroot=0

while getopts "dc:r:p:s:v:j:" opt; do
	case "$opt" in
		c) conf="$OPTARG" ;;
		j) chroot="$OPTARG" ;;
		r) repo="$OPTARG" ;;
		p) newroot="${OPTARG}" ;;
		d) set -o xtrace ;;
		s) sourcedir="${OPTARG}" ;;
		v) version="${OPTARG}" ;;
		*) usage ;;
	esac
	shift $(($OPTIND - 1))
done

[ -z "${conf}" -o -z "${repo}" ] && usage

pkgdir="$( dirname $0 )" # XXX
pkgdir="$( realpath $pkgdir )" # curdir

if [ ! -d "$repo" ]; then
	err 1 "Please create $repo dir"
fi

set -e
pre
#trap "post" HUP INT ABRT BUS TERM EXIT

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

[ -n "${newroot}" ] && root="${newroot}"
[ -n "${sourcedir}" ] && SRC_DIR="${sourcedir}"
[ -n "${version}" ] && Version="${version}"

_fakeroot="${fakeroot}${root}/"

[ -z "${SRC_DIR}" -o ! -d "${SRC_DIR}" ] && err 1 "No such source: $SRC_DIR"

if [ $chroot -ne 1 ]; then
	SRC_DIRNAME=$( basename ${SRC_DIR} )
else
	unset SRC_DIRNAME
fi

BASE_DIR="${_fakeroot}/${SRC_DIRNAME}"
mkdir -p "${BASE_DIR}"
#cp -a ${SRC_DIR}/* ${_fakeroot}/${SRC_DIRNAME}/

#cd "${SRC_DIR}" && find ${SRC_DIR} \( -type f -or -type d -or -type l \) -and -not -regex \"$JAILNODATA\" -print |sed s:${BASE_DIR}:./:g |cpio -pdmu ${1}
cd "${SRC_DIR}" && find ${SRC_DIR} \( -type f -or -type d -or -type l \) |sed s:${SRC_DIR}:./:g |cpio -pdmu ${BASE_DIR}

#find_files="find ${_fakeroot}${SRC_DIRNAME} -type f"
#find_dirs="find ${_fakeroot}${SRC_DIRNAME} -type d"
#find_size="find ${_fakeroot}${SRC_DIRNAME} -type f -exec stat -c %s {} \+"

#ex=""
#for i in ${EXCLUDE}; do
#		ex="${ex} -not -path \'${_fakeroot}${SRC_DIRNAME}${i}\'"
#done

#######################
# temporary work-around with rm -rf
for i in ${EXCLUDE}; do
	echo "Exclude location: rm -rf ${_fakeroot}${SRC_DIRNAME}${i}"
	rm -rf ${_fakeroot}${SRC_DIRNAME}${i}
done

find_files="find ${_fakeroot}${SRC_DIRNAME} -type f"
find_dirs="find ${_fakeroot}${SRC_DIRNAME} -type d"
find_size="find ${_fakeroot}${SRC_DIRNAME} -type f -exec stat -c %s {} \+"
#######################

files=
dirs=

set_files
#set_dirs
set_flatsize

if [ -f "${SRC_DIR}/.git/config" ]; then
	cd ${SRC_DIR}
	[ Version=$( git log -n1 |/usr/bin/awk '/commit /{print $2}' |head -c 8 )
fi

[ -z "${Version}" ] && Version="0.1"

cat > ${DIR}/control <<EOF
Package: ${Package}
Source: ${Package}
Version: ${Version}
Architecture: ${Architecture}
Maintainer: ${Maintainer}
Installed-Size: ${flatsize}
Depends: ${Depends}
Section: ${Section}
Priority: ${Priority}
Homepage: http://www.olevole.ru/
Description: ${Description}

EOF

echo "${files}" > ${DIR}/md5sums

cd ${DIR}
CONTROL_FILES="control md5sums"

if [ -n "${control}" ]; then
	for i in $( find ${pkgdir}/control/${control} -type f -exec basename {} \;); do
		if [ -f "${pkgdir}/control/${control}/${i}" ]; then
				cp ${pkgdir}/control/${control}/${i} ${DIR}
				CONTROL_FILES="${CONTROL_FILES} ${i}"
		fi
	done

fi

#tar zcvf control.tar.gz control md5sums
tar zcvf control.tar.gz ${CONTROL_FILES}

rm -f control md5sums

cd ${fakeroot}
tar cfz ${DIR}/data.tar.gz *

rm -rf ${fakeroot}

echo "2.0" > ${DIR}/debian-binary
cd ${DIR}

#exit 0
ar rcv ${Package}-${Version}.deb debian-binary control.tar.gz data.tar.gz

mv ${Package}-${Version}.deb ${repo}/
file -s ${repo}/${Package}-${Version}.deb
