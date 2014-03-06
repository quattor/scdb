#!/bin/sh

OS_LIST='sl510-x86_64 sl520-x86_64 sl530-x86_64 sl540-x86_64 sl550-x86_64 sl560-x86_64 sl570-i386 sl580-x86_64 sl590-x86_64 sl610-x86_64 sl620-x86_64 sl630-x86_64 sl640-x86_64'
DATE=`date +%Y%m%d`

# Verify current working directory
if [ ! -d cfg/sites/grif/repository ]; then
    echo "ERROR: this should be run from the base dir"
    exit 1
fi

# Chose versioning software
vs="echo unknown"
if [ -d .svn ]; then
    vs=svn
fi
if [ -d .git ]; then
    vs=git
fi

for os in $OS_LIST ; do
    if [ -d cfg/os/${os}/rpms/errata ]; then
        echo $os

        LAST_ERRATA_FIX=`ls -1 cfg/os/$os/rpms/errata/*-fix.tpl 2>/dev/null | grep errata/[0-9]*-fix | tail -n1 | awk 'BEGIN{FS="[/.-]"}{print $7}'`
        if [ -f cfg/os/${os}/rpms/errata/$LAST_ERRATA_FIX-fix.tpl ]; then
            echo "  Copy errata-fix from last errata ($LAST_ERRATA_FIX)"
            cp cfg/os/${os}/rpms/errata/$LAST_ERRATA_FIX-fix.tpl cfg/os/${os}/rpms/errata/$DATE-fix.tpl
            $vs add cfg/os/${os}/rpms/errata/$DATE-fix.tpl
            # echo '  Fix errata-fix name'
            sed -i -e "s/$LAST_ERRATA_FIX/$DATE/g" cfg/os/${os}/rpms/errata/$DATE-fix.tpl
        fi

        LAST_ERRATA_INIT=`ls -1 cfg/os/$os/config/os/errata/*-init.tpl | grep errata/[0-9]*-init | tail -n1 | awk 'BEGIN{FS="[/.-]"}{print $8}'`
        if [ -f cfg/os/${os}/config/os/errata/$LAST_ERRATA_INIT-init.tpl ]; then
            echo "  Copy errata-init from last errata ($LAST_ERRATA_INIT)"
            cp cfg/os/${os}/config/os/errata/$LAST_ERRATA_INIT-init.tpl cfg/os/${os}/config/os/errata/$DATE-init.tpl
            $vs add cfg/os/${os}/config/os/errata/$DATE-init.tpl
            # echo '  Fix errata-init name'
            sed -i -e "s/$LAST_ERRATA_INIT/$DATE/g" cfg/os/${os}/config/os/errata/$DATE-init.tpl
        fi

        echo '  Create errata template'
        src/utils/misc/rpmErrata.pl /www/htdocs/packages/os/$os/errata > cfg/os/$os/rpms/errata/$DATE.tpl 2> /dev/null
        $vs add cfg/os/$os/rpms/errata/$DATE.tpl
        # echo '  Fix template name'
        sed -i -e "s/rpms\/errata/rpms\/errata\/$DATE/g" cfg/os/${os}/rpms/errata/$DATE.tpl
        echo
    fi
done
