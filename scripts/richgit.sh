#!/bin/bash

MODULES="archetypes build cdk components core dev-examples showcase"
SCRIPTS=`dirname $(readlink -f $0)`
TOPDIR=`readlink -f $SCRIPTS/../..`
BRANCH="develop"
CURL=/usr/bin/curl

#MD5 - we need to trust JSON.sh and resty
JSONSH_MD5=dec0b0e06059e4eee1e5d65620354a71
RESTY_MD5=7b451ec4240eaaf73a102bcbf05ba5fe

#Colors
Brown="$(tput setaf 3)"
Green="$(tput setaf 2)"
Red="$(tput setaf 1)"
NoColor="$(tput sgr0)"
Ruler="$Green################################################$NoColor"

for_each_module() {
    EXECUTE=$*
    echo $Ruler
    for MODULE in $MODULES; do
        echo -n $Brown
        echo "$ $EXECUTE [$Green $MODULE $Brown]"
        echo -n $NoColor
        if [[ ! -d "$TOPDIR/$MODULE" ]]; then
            module_does_not_exist
        else
            pushd "$TOPDIR/$MODULE" >/dev/null
            eval "$EXECUTE"
            popd >/dev/null
        fi
    done
    echo $Ruler
}

fork_all_modules() {
    get_resty_if_required
    . $SCRIPTS/resty
    resty https://api.github.com
    for MODULE in $MODULES; do
        if [[ "$USERNAME" != "richfaces" ]]; then
            RESULT=$((POST /repos/richfaces/$MODULE/forks -u "$USERNAME:$PASSWORD" -v) 2>&1)
            if [[ $RESULT =~ "Status: 401 Unauthorized" ]]; then
                echo -n $Red
                echo "Github username / password is incorrect. Exiting."
                echo -n $NoColor
                exit 1
            elif [[ $RESULT =~ "Status: 202 Accepted" ]]; then
                echo -n $Green
                echo "Successfully forked [$Brown $MODULE $Green] in Github."
                echo -n $NoColor
            else
                echo -n $Red
                echo "Unsure of what happened when forking [$Brown $MODULE $Red] in Github. Exiting."
                echo -n $NoColor
                exit 1
            fi
        fi
    done
}

checkout_all_modules() {
    get_resty_if_required
    . $SCRIPTS/resty
    resty https://api.github.com
    get_jsonsh_if_required
    pushd $TOPDIR >/dev/null
        for MODULE in $MODULES; do
            if [[ ! -d "$MODULE" ]]; then
                if [[ $FORK == true ]]; then
                    RESULT=`GET /repos/richfaces/$MODULE/forks -u "$USERNAME:$PASSWORD"`
                    URL=`echo $RESULT | $SCRIPTS/JSON.sh | awk "/\[[0-9]+,\"ssh_url\"\]\t\"git@github\.com:$USERNAME\/.*\.git\"/" | cut -f 2 | sed "s/\"//g"`
	            echo -n $Green
	            echo "Cloning [$Brown $MODULE $Green] from your personal fork located at [$Brown $URL $Green]."
	            echo -n $NoColor
                    git clone $QUIET "$URL" "$MODULE"
                else
	            echo -n $Green
	            echo "Cloning [$Brown $MODULE $Green]."
	            echo -n $NoColor
                    git clone $QUIET "$BASE/$MODULE.git"
                fi
            else
                module_already_exists
                continue
            fi
            if [[ "$USERNAME" != "richfaces" ]]; then
                pushd $MODULE >/dev/null
                    git remote add upstream "https://github.com/richfaces/$MODULE.git"
                popd >/dev/null
            fi
        done
    popd >/dev/null
}

module_already_exists() {
    echo -n $Red
    echo "*** Module [$Green $MODULE $Red] already exists.$NoColor Skipping over it."
    echo -n $NoColor
}

module_does_not_exist() {
    echo -n $Red
    echo "*** Module [$Green $MODULE $Red] does not exist.$NoColor Skipping over it."
    echo -n $NoColor
}

pull_upstream_all_modules() {
    pushd $TOPDIR >/dev/null
    for MODULE in $MODULES; do
        if [[ ! -d "$MODULE" ]]; then
            module_does_not_exist
            continue
        fi
        if [[ "$USERNAME" != "richfaces" ]]; then
            pushd $MODULE >/dev/null
            RESULT=`git stash`
            echo -n $Brown
            echo "Updating [$Green $MODULE $Brown] from upstream"
            echo -n $NoColor
            git fetch $QUIET
            git pull $QUIET --rebase upstream $BRANCH
            if [[ ! $RESULT =~ "No local changes to save" ]]; then
                git stash pop $QUIET
            fi
            popd >/dev/null
        else
            pushd $MODULE >/dev/null
            RESULT=`git stash`
            echo -n $Brown
            echo "Updating [$Green $MODULE $Brown] from origin"
            echo -n $NoColor
            git fetch $QUIET
            git pull $QUIET --rebase origin $BRANCH
            if [[ ! $RESULT =~ "No local changes to save" ]]; then
                git stash pop $QUIET
            fi
            popd >/dev/null
        fi
    done
    popd >/dev/null
}

usage() {
    cat << EOF
usage: $0 options

Clones the modules ($MODULES) from github using either your forked modules or the richfaces modules. If cloning forked modules it will automatically set the upstream remote.

OPTIONS:
   -h      Show this message.
   -v      Be verbose.
   -p      Pull updates rather than clone fresh modules.
   -e      Run a command against each module
   -f      Automatically fork the source before cloning it (you will be prompted for your github password).
   -s      Run git status on all modules
   -t      Transport one of http, git or ssh (default).
   -u      Github username to checkout with required for http transport or to ensure checkout from your forked modules.
   -m      Specify the modules to clone from github in a space seperated quoted string ie. -m "core cdk components". You may also use "all" as an alias for ($MODULES).
   -b      Specify the branch to pull updates from defaults to "develop".
EOF
}

get_resty_if_required() {
    if [[ ! -f $SCRIPTS/resty ]]; then
        echo "Fetching resty to allow us to fork on Github."
        curl -s -L http://github.com/micha/resty/raw/58560a1161a0a31ea9263acdfbd16952757414bd/resty > $SCRIPTS/resty
        MD5=`md5sum $SCRIPTS/resty | cut -d " " -f 1`
        if [[ $RESTY_MD5 != $MD5 ]]; then
            echo "resty MD5 does not match, deleting and exiting."
            rm $SCRIPTS/resty
            exit 1
        fi
    fi
}

get_jsonsh_if_required() {
    if [[ ! -f $SCRIPTS/JSON.sh ]]; then
        echo "Fetching JSON.sh to allow us to get our personal fork URL on Github."
        curl -s -L https://raw.github.com/dominictarr/JSON.sh/360b592eea3b65a20a10b5110cde976b0a5e4872/JSON.sh > $SCRIPTS/JSON.sh
        MD5=`md5sum $SCRIPTS/JSON.sh | cut -d " " -f 1`
        if [[ $JSONSH_MD5 != $MD5 ]]; then
            echo "JSON.sh MD5 does not match, deleting and exiting."
            rm $SCRIPTS/JSON.sh
            exit 1
        fi
        chmod +x $SCRIPTS/JSON.sh
    fi
}

QUIET="-q"
USERNAME=richfaces
PASSWORD=""
STATUS=false
TYPE=ssh
PULL=false
FORK=false
CURL_FOUND=false

while getopts "hvpsefu:b:t:m:" OPTION
do
     case $OPTION in
    h)
        usage
        exit
        ;;
    v)
        QUIET=""
        ;;
        p)
        PULL=true
        ;;

    e)
        EACH=true
        ;;
    f)
        FORK=true
        type -P $CURL >/dev/null && CURL_FOUND=true || CURL_FOUND=false
        if [[ CURL_FOUND == false ]]; then
            echo "$CURL not found you cannot use automatic forking."
            exit 1
        fi
        if [[ $USERNAME != "richfaces" ]]; then
            read -p "Enter your Github password:" -s PASSWORD
            echo ""
        fi
        ;;
    u)
        USERNAME=$OPTARG
        ;;
    b)
        BRANCH=$OPTARG
        ;;
    s)
        STATUS=true
        ;;
        t)
            TYPE=$OPTARG
            ;;
    m)
        MODULES=`echo "$OPTARG" | sed "s/all/$MODULES/g"`
        ;;
    ?)
        usage
        exit 1
        ;;
     esac
done

shift $(($OPTIND - 1))
CMD_ARGS=$*

case "$TYPE" in
    http)
        BASE=https://$USERNAME@github.com/$USERNAME
        ;;
    git)
        BASE=git://github.com/$USERNAME
        ;;
    ssh)
        BASE=git@github.com:$USERNAME
        ;;
    [?])
        echo "supported types: http, git, ssh"
        exit 1
        ;;
esac

if [[ $EACH == true ]]; then
    for_each_module $CMD_ARGS
elif [[ $STATUS == true ]]; then
    for_each_module 'git status'
else
    if [[ $PULL == false ]]; then
        if [[ $FORK == true && $USERNAME != "richfaces" ]]; then
            fork_all_modules
        fi
        checkout_all_modules
    else
        pull_upstream_all_modules
    fi
fi
