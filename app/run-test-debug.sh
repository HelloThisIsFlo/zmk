#!/bin/sh
#
# Copyright (c) 2020 Peter Johanson; Cody McGinnis; Okke Formsma
#
# SPDX-License-Identifier: MIT
#
set -e 
set -x

if [ -z "$1" ]; then
	echo "Usage: ./run-test-debug.sh <path to testcase>"
	exit 1
fi

path="$1"
if [ $path = "all" ]; then
	path="tests"
fi

testcases=$(find $path -name native_posix.keymap -exec dirname \{\} \;)
num_cases=$(echo "$testcases" | wc -l)
if [ $num_cases -gt 1 ]; then
	echo "" > ./build/tests/pass-fail.log
	echo "$testcases" | xargs -l -P 4 ./run-test-debug.sh
	err=$?
	sort -k2 ./build/tests/pass-fail.log
	exit $err
fi

testcase="$1"
echo "Running $testcase:"

west build -d build/$testcase -b native_posix_64 --pristine -- -DZMK_CONFIG=`pwd`/$testcase
if [ $? -gt 0 ]; then
	echo "FAIL: $testcase did not build" 
else
	./build/$testcase/zephyr/zmk.exe | tee build/$testcase/keycode_events_full.log | sed -e "s/.*> //" | sed -n -f $testcase/events.patterns > build/$testcase/keycode_events.log
	cat build/$testcase/keycode_events_full.log
	cat build/$testcase/keycode_events.log
	diff -au $testcase/keycode_events.snapshot build/$testcase/keycode_events.log
	if [ $? -gt 0 ]; then
		if [ -f $testcase/pending ]; then
			echo "PEND: $testcase" 
			exit 0
		else
			echo "FAIL: $testcase" 
			exit 1
		fi
	else
		echo "PASS: $testcase" 
		exit 0
	fi
fi