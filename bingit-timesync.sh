#!/bin/sh

set -e

# original are: https://gist.github.com/jeffery/1115504
####
# Helper script to update the Last modified timestamp of files in a Git SCM
# Projects working Copy
#
# When you clone a Git repository, it sets the timestamp of all the files to the
# time when you cloned the repository.
#
# This becomes a problem when you want the cloned repository, which is part of a 
# Web application have a proper cacheing mechanism so that it can re-cache files
# (into a webtree) that have been modified since the last cache.
#
# @see http://stackoverflow.com/questions/1964470/whats-the-equivalent-of-use-commit-times-for-git
#
# Author: Jeffery Fernandez <jeffery@fernandez.net.au>
####

####
# Author: TsT worldmaster.fr <tst2005@gmail.com>
#
# Improvement :
# - dry-run by default (use -f to apply time change)
# - pass files to check as argument
# - do not time sync modified files
# - do not time sync untracked files
# - ...
#
# TODO:
# - Linux version improved, to the same for MacOS X and FreeBSD
# - ...
####

# Get the last revision hash of a particular file in the git repository
getFileLastRevision() {
	git rev-list HEAD -- "$1" | head -n 1
}

# Extract the actual last modified timestamp of the file and Update the time-stamp
# ... for Linux
updateFileTimeStamp() {
	# Extract the file revision
	local FILE_REVISION_HASH="$(getFileLastRevision "$1")"

	# if target does not exists and it's is not a [dead]link, raise an error
	if [ ! -e "$1" ] && [ ! -h "$1" ]; then
		if [ -n "$(git ls-files -t -d -- "$1")" ]; then
			if $verbose; then echo "?  $1 (deleted)"; fi
			return
		fi
		echo >&2 "ERROR: Unknown bug ?! No sych target $1"
		return 1
	fi

	local tracked="$(git ls-files -t -c -- "$1")"
	if [ -z "$tracked" ]; then
		if $verbose; then echo "?  $1"; fi
		return
	fi

	# Extract the last modified timestamp
	# Get the File last modified time
	local FILE_MODIFIED_TIME="$(git show --pretty=format:%at --abbrev-commit ${FILE_REVISION_HASH} | head -n 1)"
	if [ -z "$FILE_MODIFIED_TIME" ]; then
		echo "?! $1 (not found in git)"
		return
	fi

	# Check if the file is modified
	local uncommited="$(git ls-files -t -dm -- "$1")"

	# for displaying the date in readable format
	#local FORMATTED_TIMESTAMP="$(date --date="${FILE_MODIFIED_TIME}" +'%d-%m-%Y %H:%M:%S %z')"
	local FORMATTED_TIMESTAMP="@${FILE_MODIFIED_TIME}"

	# Modify the last modified timestamp
	#echo "[$(date -d "$FORMATTED_TIMESTAMP")]: $1"
	#echo "$FILE_MODIFIED_TIME $1"
	local current_mtime="$(stat -c %Y -- "$1")"
	if $debug; then
		echo >&2 "DEBUG: $1 (git_time=$FILE_MODIFIED_TIME current_time=$current_mtime delta=$(( ${current_mtime:-0} - ${FILE_MODIFIED_TIME:-0} )))"
	fi
	if [ "$current_mtime" = "$FILE_MODIFIED_TIME" ]; then
		if ${verbose:-true}; then echo "ok $1"; fi
		return
	fi
	if [ -n "$uncommited" ]; then
#		if ${force:-false}; then
#			echo "C  $1 (modified, not commited, $(( $current_mtime - $FILE_MODIFIED_TIME ))s recent)"
#			do it
#			return
#		fi
#			
		echo "C  $1 (modified, not commited, $(( $current_mtime - $FILE_MODIFIED_TIME ))s recent)"
		return
	fi
	if ${dryrun:-true}; then
		echo "!! $1 (desync: $(( $current_mtime - $FILE_MODIFIED_TIME ))s, no change)"
		return
	fi
	echo "!! $1 (desync: $(( $current_mtime - $FILE_MODIFIED_TIME ))s, syncing...)"
	[ -h "$1" ] && touch -h -d "$FORMATTED_TIMESTAMP" -- "$1" || \
	touch -d "$FORMATTED_TIMESTAMP" -- "$1"
}

# ... for FreeBSD and Mac OS X
updateFileTimeStamp2() {
	# Extract the file revision
	local FILE_REVISION_HASH="$(getFileLastRevision "$1")"

	# Extract the last modified timestamp
	# Get the File last modified time
	local FILE_MODIFIED_TIME="$(git show --pretty=format:%ai --abbrev-commit ${FILE_REVISION_HASH} | head -n 1)"

	# Format the date for updating the timestamp
	local FORMATTED_TIMESTAMP="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "${FILE_MODIFIED_TIME}" +'%Y%m%d%H%M.%S')"
		
	# Modify the last modified timestamp
	touch -t "${FORMATTED_TIMESTAMP}" -- "$1"
}

# Make sure we are not running this on a bare Repository
is_not_base_repo() {
	case "$(git config core.bare)" in
		false)	;;
		true)
			echo "$(pwd): Cannot run this script on a bare Repository"
			return 1
		;;
		*)	echo "$(pwd): Error appended during core.bare detection. Are you really inside a repository ?"
			return 1
	esac
	return 0
}


force=false
dryrun=false
verbose=true
debug=false
while [ $# -gt 0 ]; do
	case "$1" in
		--) shift; break ;;
		-f) force=true ;;
		-n|--dryrun|--dry-run) dryrun=true ;;
		-v) verbose=true ;;
		-q) verbose=false ;;
		--debug) debug=true ;;
		*) break
	esac
	shift
done

# Obtain the Operating System
case "${OS:-$(uname)}" in
	  'Linux') ;;
	  'Darwin'|'FreeBSD')
		updateFileTimeStamp() { updateFileTimeStamp2 "$@"; }
	  ;;
	  *)
		echo >&2 "Unknown Operating System to perform timestamp update"
		exit 1
esac

updateFileTimeStampInCwd() {
	is_not_base_repo || return

	git ls-files -z \
	| tr '\0' '\n' \
	| (
	IFS="$(printf '\n')"
	while read -r file; do
		if [ -z "$(git ls-files -t -d -- "$file")" ]; then
			updateFileTimeStamp "${file}"
		fi
	done
	)
}

if [ $# -eq 0 ]; then
	# Loop through and fix timestamps on all files in our checked-out repository
	updateFileTimeStampInCwd
else
	need_check_bare=true
	# Loop through and fix timestamps on all specified files
	for file in "$@"; do
		if [ -d "$file" ] && [ ! -h "$file" ]; then # is a real directory (not a symlink to a directory)
			echo "now inside $file"
			( cd -- "$file" && updateFileTimeStampInCwd || true; )
		else
			if $need_check_bare; then
				is_not_base_repo || continue
				need_check_bare=false
			fi
			updateFileTimeStamp "${file}"
		fi
	done
fi

