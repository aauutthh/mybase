#!/bin/bash
# cygpackage get -f -p pkg -[R remote|L local] addr 
NEEDED_COMMANDS_NOTEXSIST_LIST=/tmp/needed_commands_list.$$
arch=`arch`
saving_cmd=""
this=$(readlink -f $0)

rm -f $NEEDED_COMMANDS_NOTEXSIST_LIST
function getcommand() {
CMD_NEED=`which $1 2> /dev/null`
if test "-${CMD_NEED}-" = "--" 
then
    echo $1 >> ${NEEDED_COMMANDS_NOTEXSIST_LIST}
fi
echo $CMD_NEED
}
function list_need_command_and_delete() {
if test -e "$NEEDED_COMMANDS_NOTEXSIST_LIST"
then
    echo You must install :
    cat $NEEDED_COMMANDS_NOTEXSIST_LIST
    rm -f $NEEDED_COMMANDS_NOTEXSIST_LIST
    exit 1
fi
}


WGET=`getcommand wget`
BZIP2=`getcommand bzip2 `
TAR=`getcommand tar `
GAWK=`getcommand awk `
FIND=`getcommand find `

list_need_command_and_delete

function usage() {
echo " cygpackage get -p pkg -[R remote|L local] addr -s saving_work_path [-f force_get_level] "
exit;
}

function show_mirror_struct() {
cat << END
mirror_root:
.
└── x86_64
    ├── md5.sum
    ├── release
    ├── setup.bz2
    ├── setup.bz2.sig
    ├── setup.ini
    └── setup.ini.sig
└── x86
    ├── md5.sum
    ├── release
    ├── setup.bz2
    ├── setup.bz2.sig
    ├── setup.ini
    └── setup.ini.sig

struct of release:
.
├── package1
├── package2
    ├── file...
    ├── md5.sum
    └── setup.hint

END
}


function version()
{
    echo "Written by lwd"
    echo ""
    echo "Copyright (c) 2014-10 lwd.  Released under the GPL."
}

# cmd : get
cmd=$1
shift
if test "-$cmd-" = "--" -o "-$cmd" = "--h"; then
    usage
fi

# getmethod 0:未定义 1:从远程镜像获取 2:从本地镜像获取
getmethod=0
force_saving=0
while test $# -gt 0
do
    case "$1" in
        -f)
            force_saving=$2
            shift ;shift
            ;;

        -R)
            remote_addr=$2
            getmethod=1
            saving_cmd="$saving_cmd -R $remote_addr "
            shift ; shift
            ;;

        -L)
            local_addr=$2
            getmethod=2
            saving_cmd="$saving_cmd -L $local_addr "
            shift ; shift
            ;;

        -s)
            saving_work_path=$2
            saving_cmd="$saving_cmd -s ./ "
            shift ; shift
            ;;

        -p)
            pkgs="$pkgs $2"
            shift ; shift
            ;;

    esac
done

function checkpackages()
{
    if test "-$pkgs-" = "--"
    then
        echo Nothing to do, exiting
        exit 0
    fi
}

function prepareworkspace()
{
    if test -z "$saving_work_path" ; then
        exit;
    else
        echo Working directory is $saving_work_path
        # all work is running in {saving_work_path}
        mkdir -p "$saving_work_path"
        mkdir -p "$saving_work_path/bak"
        mkdir -p "$saving_work_path/$arch"
        cd "$saving_work_path"
        if test ! -e "$arch/downloaded.db"
        then
            touch "$arch/downloaded.db"
        fi
    fi
}

function getfile_chk() {
if [ $# -lt 2 ]; then
    return 1
fi
filepath=$1
digest=$2

if [ -e "$filepath" ] ; then
    digactual=`md5sum $install | awk '{print $1}'`
    if  [ $digest = $digactual ] ; then
        echo MD5 sum match,skip getting 
        return 0
    fi
fi
getfile $filepath

digactual=`md5sum $install | awk '{print $1}'`
if ! [ "$digest" = "$digactual" ] ; then
    echo MD5 sum not match,getfile fail
    return 1
fi

}

function getfile() {
if [ $# -lt 1 ]; then
    return 1
fi
filepath=$1
pathname=${filepath%/*}
mkdir -p $pathname

if [ -e "$filepath" ] ; then
    mkdir -p "bak/$pathname"
    mv -f "$filepath" "bak/$filepath"
fi

case "$getmethod" in
    0)
        usage;
        exit;
        ;;
    1)
        WGET -c "$remote_addr/$filepath" -O $filepath
        if  [ $? -ne 0 ]  ;then
            echo "can't get $filepath"
            return 1
        fi
        ;;
    2)
        if [-e "$local_addr/$filepath" ] ;then
            echo "can't get $filepath"
            return 1
        else
            cp -f $local_addr/$filepath $filepath
        fi
        ;;
esac

}

function getsetup()
{
    echo Updated setup.ini

    if test -e "$arch/setup.ini" ; then
        timenow=`stat -c %X /dev/zero`
        timefile=`stat -c %X $arch/setup.ini`
        timedef=`expr $timenow - $timefile`
        if [ $timedef -lt 1800 ] ; then
            echo "setup.ini is up to date"
            return 0
        else
            mv $arch/setup.ini $arch/setup.ini-save
        fi
    else
        touch $arch/setup.ini-save
    fi


    getfile $arch/setup.bz2 

    if [ $? -eq 1 ];then
        getfile $arch/setup.ini 
        if [ $? -eq 1 ];then
            echo Error updating setup.ini, reverting
            mv $arch/setup.ini-save $arch/setup.ini
            return 1
        fi
    else
        bunzip2 $arch/setup.bz2
        mv -f $arch/setup $arch/setup.ini
    fi

    touch $arch/setup.ini
    return 0
}

checkpackages
#findworkspace
prepareworkspace
getsetup

for pkg in $pkgs
do
# 检查是否已下载
    already=`grep -c "^$pkg " $arch/downloaded.db`
    if test $already -ge 1
    then
        echo Package $pkg is already installed, skipping
        if [ $force_saving -gt 0 ] ; then
            echo "force saving "
        else
            continue
        fi
    fi
    echo ""

    # look for package and save desc file

# 查找setup.ini是否有package信息
    #mkdir -p "release/$pkg"
    cat $arch/setup.ini | awk > "${pkg}.desc" -v package="$pkg" \
        'BEGIN{RS="\n\n@ "; FS="\n"} {if ($1 == package) {desc = $0; px++}} \
        END {if (px == 1 && desc != "") print desc; else print "Package not found"}'

    desc=`cat "${pkg}.desc"`
    if test "-$desc-" = "-Package not found-"
    then
        echo Package $pkg not found or ambiguous name, exiting
        #rm -r "$arch/release/$pkg"
        exit 1
    fi
    echo "Found package <$pkg> in setup.ini"
    echo "downloading <$pkg>"

    # md5 chksum
    digest=`cat "${pkg}.desc" | awk '/^install: / { print $4; exit }'`


    # pick the latest version, which comes first
    install=`cat "${pkg}.desc" | awk '/^install: / { print $2; exit }'`

    if test "-$install-" = "--"
    then
        echo "Could not find \"install\" in package description: obsolete package?"
        exit 1
    fi

    file=`basename $install`
    #filepath=${install%/*}
    #mkdir -p $filepath
    #cp -f $local_addr/$install $filepath
    getfile_chk $install $digest

    if [ $? -eq 1 ]; then
        echo "get $install fail"
        exit 1
    fi


    # update the downloaded package database

# 更新 数据库
    cat "$arch/downloaded.db" | awk > /tmp/awk.$$ -v pkg="$pkg" -v bz="$file" \
        '{if (ins != 1 && pkg < $1) {print pkg " " bz " 0"; ins=1}; print $0} \
        END{if (ins != 1) print pkg " " bz " 0"}'
    mv "$arch/downloaded.db" "$arch/downloaded.db-save"
    mv /tmp/awk.$$ "$arch/downloaded.db"

    # recursively install required packages

# 检查依赖情况
    echo > /tmp/awk.$$ '/^requires: / {s=gensub("(requires: )?([^ ]+) ?", "\\2 ", "g", $0); print s}'
    requires=`cat "${pkg}.desc" | awk -f /tmp/awk.$$`
    rm -f "${pkg}.desc"

    warn=0
    req_cmd=
    if ! test "-$requires-" = "--"
    then
        echo "Package <$pkg> requires the following packages, installing:"
        echo $requires
        for package in $requires
        do
            already=`grep -c "^$package " $arch/downloaded.db`
            if test $already -ge 1
            then
                if ! [ $force_saving -gt 1 ];then  # 第二层包, force_saving >= 2 才会进行第二层强制存取
                echo Package $package is already installed, skipping
                continue
                else
                echo Package $package is already installed, force saving
                fi
            fi
            req_cmd="$req_cmd -p $package"
            if ! test $? = 0 ; then warn=1; fi
        done
echo $req_cmd
        if ! test "-$req_cmd-" = "--"
        then
            if [ $force_saving -gt 1 ] ; then
                force_saving_tmp=` expr $force_saving - 1 `
                saving_cmd="$saving_cmd -f $force_saving_tmp"
            fi
            echo ""
            echo "========"
            echo "$this get $req_cmd $saving_cmd"
            $this get $req_cmd $saving_cmd
            echo "===="
        fi
    fi


done
















