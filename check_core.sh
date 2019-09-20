#!/bin/bash

curtime=$(date +%s%N)

coresdir=./ygopro/cores/

mkdir -p $coresdir

lastdir=""
prevdir=$PWD
cd ./ygopro/cores
for d in */; do
	if [ "${d}" == "*/" ]; then
		break
	fi
	lastdir="${d}"
	break
done
cd $prevdir
create=false
if [[ "$OSTYPE" == "linux-gnu" ]]; then
	corename="libocgcore.so"
elif [[ "$OSTYPE" == "darwin"* ]]; then
	corename="libocgcore.dylib"
elif [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
	corename="ocgcore.dll"
fi
if [ -z "${lastdir}" ]; then
	create=true
else
	coredir="./ygopro/cores/${lastdir}"
	if cmp --silent "${coredir}${corename}" "./ygopro/expansions/live2019/${corename}"; then
		create=false
	else
		create=true
	fi
fi
if [ "$create" = true ]; then
	newdir="${coresdir}${curtime}/"
	mkdir "${newdir}"
	cp "./ygopro/expansions/live2019/$corename" "${newdir}"
fi
