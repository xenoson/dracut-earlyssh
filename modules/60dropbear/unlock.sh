#!/bin/sh

#https://www.freedesktop.org/wiki/Software/systemd/PasswordAgents/

#for productivity use pwAgent
pwAgent="/usr/bin/systemd-tty-ask-password-agent --query"

# Don't allow more ask files in askDir than maxCount
maxCount="10"

askDir='/var/run/systemd/ask-password'
#debug
#askDir='./ask-p.d'
askFileMask='ask.*'
expectedSocketFileName='sck' #name before the dot
hooksDir='/lib/dracut/hooks'
initqueueDir='initqueue'
finishedDir="${initqueueDir}/finished"
dracutCryptsetup='90-crypt.sh*'

#Only set this to No is for demonstration of race condition, not for productivity use
waitLock="Yes"

#make shure these are unique and dont collide with something else
askPauseLock="${askDir}/unlock-ask-pause-lock"
askPauseLocked="${askDir}/unlock-ask-pause-locked"
askPauseScript="${hooksDir}/${initqueueDir}/unlock-ask-pause.sh"

waitSeconds="2"
fakeLockWait="2"

verbose="0"


processAskFiles() {
    local op="${1}"
    local askFiles="${2}"
    local askCount="0"
    
    for askFile in ${askFiles}
    do
        if [ -f "${askFile}" -o "${askFile}" != "${askFiles}" ]
        then
            askCount="$(($askCount+1))"
        fi
    done
    [ "${op}" = "count" ] && printf "${askCount}"
}

installLock() {
    local lockFile="${1}"
    local lockedFile="${2}"
    local scriptFile="${3}"

#this here-document will be sourced by dracut-initqueue
cat<<eof>>"${scriptFile}"
while [ -f "${lockFile}" ]
do
    if [ ! -f "${lockedFile}" ]
    then
        printf "" > "${lockedFile}"
        info "lock established, ${lockedFile} created"
    else
        info "pausing main loop as long as ${lockFile} is there - waiting for password entry to complete"
        sleep 1
    fi
done
if [ -f "${lockedFile}" ]
then
    rm -f -- "${lockedFile}"
    info "lock released, ${lockedFile} removed"
else
    info "lock file ${lockFile} not here, doing nothing"
fi
eof

}

pauseInitQ() {
    local op="${1}"
    local lockFile="${2}"
    local lockedFile="${3}"
    local scriptFile="${4}"
    local fakeLock="0"
    
    if [ "${op}" = "lock" ]
    then
        if [ ! -f "${lockFile}" ]
        then
            printf "" > "${lockFile}"
            LOCKED="1"
            installLock "${lockFile}" "${lockedFile}" "${scriptFile}"

            while [ ! -f "${lockedFile}" ]
            do
                [ "${verbose}" -eq "1" ] && printf "waiting for lockedFile %s to appear"\\n "${lockedFile}"
                sleep "${waitSeconds}"
                if [ "${fakeLock}" -eq "${fakeLockWait}" ]
                then
                    [ "${verbose}" -eq "1" ] && printf "this is the good case, dracut is not looping. safe to create lockedFile %s here"\\n "${lockedFile}"
                    printf "" > "${lockedFile}"
                    
                fi
                fakeLock="$((${fakeLock}+1))"
            done
            [ "${verbose}" -eq "1" ] && printf "dracut is pausing..."\\n
        else
            printf "Bug, cannot be: Lockfile already exists"\\n
        fi


    elif [ "${op}" = "unlock" ]
    then
        if [ -f "${lockFile}" ]
        then
            rm -f -- "${lockFile}"

            while [ -f "${lockedFile}" ]
            do
                [ "${verbose}" -eq "1" ] && printf "waiting for lockedFile %s to disappear"\\n "${lockedFile}"
                sleep "${waitSeconds}"
                if [ "${fakeLock}" -eq "${fakeLockWait}" ]
                then
                    #this never happened in both cases, dracut should be looping after new devices are available
                    [ "${verbose}" -eq "1" ] && printf "dracut is not looping. probably safe to delete lockedFile %s here"\\n "${lockedFile}"
                    rm -f -- "${lockedFile}"
                fi
                fakeLock="$((${fakeLock}+1))"
            done
            [ "${verbose}" -eq "1" ] && printf "dracut is running..."\\n
            rm -f -- "${scriptFile}"
            LOCKED="0"
        else
            printf "Bug, cannot be: Lockfile not there"\\n
        fi
    fi

}

processFinishedFiles() {
    local op="${1}"
    local hDir="${2}"
    local qDir="${3}"
    local fPattern="${4}"
    local finishedFileCount="0"

    for finishedFile in "${hDir}"/"${qDir}"/${fPattern}
    do
        if [ -f "${finishedFile}" -o "${finishedFile}" != "${hDir}/${qDir}/${fPattern}" ]
        then
            finishedFileName="${finishedFile##/*/}"
            if [ "${op}" = "wait" ]
            then
                until processFinishedFiles "status" "${hDir}" "${qDir}" "${finishedFileName}"
                do
                    [ "${verbose}" -eq "1" ] && printf "waiting for file %s to reach success"\\n "${finishedFile}"
                    sleep "${waitSeconds}"
                    [ "$(processAskFiles "count" "${askFiles}")" -gt "0" ] && return 1
                done
                [ "${verbose}" -eq "1" ] && printf "file %s reached success"\\n "${finishedFile}"
            fi

            if [ "${op}" = "status" ]
            then
                { [ -e "${finishedFile}" ] && ( . "${finishedFile}" ) ; } || return 1
                return 0
            fi
            
            [ "${op}" = "count" ] && finishedFileCount="$(($finishedFileCount+1))"
        fi
    done
    [ "${op}" = "count" ] && printf "${finishedFileCount}"
    return 0
}

cleanup() {
    stty | grep -q '-echo' && stty echo && echo
    [ "${LOCKED}" -eq "1" ] && pauseInitQ "unlock" "${askPauseLock}" "${askPauseLocked}" "${askPauseScript}"
    echo "
premature but clean exit.
Note!

The purpose of this script is to bring up all dependent cryptsetup devices at once 
without an interfering lvm_scan triggered by dracut in between that can cause degraded activation of lvm raids. 
This job cannot be done after entering some passwords, quitting and running unlock again. 
"
    exit "$1"
}

#
#Main
#

LOCKED="0"
#crtl + c = INT
trap 'cleanup 0' TERM KILL INT

askFiles="${askDir}"/"${askFileMask}"
askCount="$(processAskFiles "count" "${askFiles}")"

if [ "${askCount}" -eq "0" ]
then
    printf "no 'ask.*' files found in askDir=${askDir}"\\n\\n
    cleanup "0"
fi

if [ "${askCount}" -ge "${maxCount}" ]
then
    printf "Refusing to process %d password ask files! Should this be sane increase \$Maxcount value."\\n "${askCount}"
    cleanup "1"
fi    

ech='printf %s'
srpX="/lib/systemd/systemd-reply-password"
#debug
#srpX="/bin/cat"
srpOp="1"
#debug
#srpOp=">"

if [ ! -x "${srpX}" ]
then
    printf "Specified \"%s\" is not executable. Exiting."\\n "${srpX}"
    cleanup "1"
fi

#with a failed password apptempt, a new ask file is generated, this takes some time
#after two attempts no more files are there

until [ "${askCount}" -eq "0" ]
do
    [ "${waitLock}" = "Yes" -a "${LOCKED}" -eq "0" ] && pauseInitQ "lock" "${askPauseLock}" "${askPauseLocked}" "${askPauseScript}"
    

    ${pwAgent}

    
    #last resort, wait for devices to come up
    [ "${LOCKED}" -eq "1" ] && processFinishedFiles "wait" "${hooksDir}" "${finishedDir}" "${dracutCryptsetup}"

    askCount="$(processAskFiles "count" "${askFiles}")"
    #debug
    #askCount="0" #
done

[ "${LOCKED}" -eq "1" ] && pauseInitQ "unlock" "${askPauseLock}" "${askPauseLocked}" "${askPauseScript}"

[ "${verbose}" -eq "1" ] && echo "final exit"

#exits the sh after sourcing this script
exit 0

