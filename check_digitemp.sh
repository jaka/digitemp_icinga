#!/bin/bash
#
# Plugin for Nagios/Icinga to monitor temperature with a 1-wire temperature sensor
# (c) 2010 Stefan Schatz (http://www.osbg.at/)
# (c) 2017 jaka (http://github.com/jaka/)
#
### You are free to use this script under the terms of the GNU Public License.
#
# Installation guidelines:
# needed software: digitemp (e.g. apt-get install digitemp)
#
# Copy the script check_digitemp.sh (this file) to the check-plugins-directory
# e.g. /usr/lib/nagios/plugins and make it executable, e.g.
# chmod +x/usr/lib/nagios/plugins/check_digitemp.sh
#
# Install sudo and edit the file /etc/sudoers. Insert
# nagios ALL=(ALL) NOPASSWD: /usr/bin/digitemp_DS9097
#
# Tested Systems: Debian
#
# Exit Codes:
# 0 OK       Temperature checked and everything is ok
# 1 Warning  Temperature above "warning" threshold
# 2 Critical Temperature above "critical" threshold
# 3 Unknown  Invalid command line arguments or could not read the sensor
#
# Example: check_digitemp -w 22.10 -c 25.00 -p
# 21.81 C - OK        (exit code 0)
# 23.00 C - WARNING   (exit code 1)
# 26.23 C - CRITICAL  (exit code 2)
#
#
# Icinga integration:
# 1. Add a command to /etc/nagios-plugins/config/digitemp.cfg like this:
#
#    ### DigiTemp temperature check command ###
#    define command{
#        command_name    check_digitemp
#        command_line    $USER1$/check_digitemp.sh -w $ARG1$ -c $ARG2$ -p
#        }
#
# 2. Tell Icinga to monitor the temperature by adding a service line like
#    this to your service.cfg file:
#
#    ### DigiTemp Temperature check Service definition ###
#    define service{
#        use                             generic-service
#        host_name                       localhost
#        service_description             Temperature
#        is_volatile                     0
#        check_period                    24x7
#        max_check_attempts              3
#        normal_check_interval           5
#        retry_check_interval            2
#        contact_groups                  admins
#        notification_interval           240
#        notification_period             24x7
#        notification_options            w,u,c,r
#        check_command                   check_digitemp!30.00!50.00
#        }
#normal_check_interval

#------------------------------------------------------------------------------
# define vars...
#------------------------------------------------------------------------------
PROGNAME="${0##*/}"
PROGPATH="$(dirname ${0})"
VERSION="0.6"
AUTHOR="(c) 2010 Stefan Schatz (http://www.osbg.at/), 2017 jaka (http://github.com/jaka/)"

#------------------------------------------------------------------------------
# exit codes
#------------------------------------------------------------------------------
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3


#------------------------------------------------------------------------------
# check user
#------------------------------------------------------------------------------
if [ "`whoami`" == "root" ]; then
    echo "TEMP - UNKNOWN - User should not be root!"
    exit $STATE_UNKNOWN
fi


#------------------------------------------------------------------------------
# check digitemp installation
#------------------------------------------------------------------------------
which digitemp_DS9097 >/dev/null 2>&1 || {
    echo "TEMP - UNKNOWN - Digitemp binary was not found!"
    exit $STATE_UNKNOWN
}


#------------------------------------------------------------------------------
function generate_digitemp_config {
#------------------------------------------------------------------------------
    NR=`lsmod | grep pl2303 | wc -l`
    [ $NR -eq 0 ] && {
        echo "Loading module pl2303 "
        modprobe pl2303 >/dev/null 2>&1 && echo "OK" || echo "FAILED"
    }

    [ -f "$HOME/.digitemprc" ] || {
        echo "-----------------------------------------------"
        echo -n "$DIGITEMP -i -s /dev/ttyUSB0 ...... "
        $DIGITEMP -i -s /dev/ttyUSB0 -c "$HOME/.digitemprc" >/dev/null 2>&1 && echo "OK" || echo "FAILED"
        echo "-----------------------------------------------"
        echo ""
    }
}


#------------------------------------------------------------------------------
function print_version {
#------------------------------------------------------------------------------
    echo "$PROGNAME: $VERSION $AUTHOR"
}

#------------------------------------------------------------------------------
function print_usage {
#------------------------------------------------------------------------------
    echo "Usage: $PROGNAME [-w NN.NN] [-c NN.NN] [-p] [-d]"
    echo "Usage: $PROGNAME -h|--help"
    echo "Usage: $PROGNAME -v|--version"
    echo ""
}

#------------------------------------------------------------------------------
function print_help {
#------------------------------------------------------------------------------
    print_version
    echo ""
    echo "1-Wire Temperature monitor plugin with digitemp for Icinga"
    echo "Description of the parameters:"
    echo " -w: threshold for warning temperature (default: 25.00° C)"
    echo " -c: threshold for critical temperature (default: 30.00° C)"
    echo " -p: send perfdata to nagios (default: false)"
    echo " -d: debug mode"
    echo ""
    print_usage
    echo ""
}


#------------------------------------------------------------------------------
# generate digitemp config
#------------------------------------------------------------------------------
DIGITEMP="sudo `which digitemp_DS9097`"
generate_digitemp_config


#------------------------------------------------------------------------------
# get and check the command line arguments
#------------------------------------------------------------------------------
### default values ###
DEBUG="false"
TRESH_WARNING="25.00"
TRESH_CRITICAL="30.00"
PERFDATA="false"

while getopts  "hvdpw:c:s:" flag; do
    case ${flag} in
        d)  DEBUG="true"
            if [ "${DEBUG}" = "true" ]; then echo "DEBUG => is enabled!"; fi
        ;;
        w)  TRESH_WARNING="$(echo ${OPTARG} | egrep '^[0-9]?[0-9][,:\.][0-9][0-9]$')"
            if [ "${DEBUG}" = "true" ]; then echo "Warning State: > ${TRESH_WARNING}° C"; fi
            if [ "${TRESH_WARNING}" = "" ]; then echo "TEMP - UNKNOWN - bad option -w ${OPTARG}!" ; print_help ; exit ${STATE_UNKNOWN}; fi
        ;;
        c)  TRESH_CRITICAL="$(echo ${OPTARG} | egrep '^[0-9]?[0-9][,:\.][0-9][0-9]$')"
            if [ "${DEBUG}" = "true" ]; then echo "Critical State: > ${TRESH_WARNING}° C"; fi
            if [ "${TRESH_CRITICAL}" = "" ]; then echo "TEMP - UNKNOWN - bad option -c ${OPTARG}!" ; print_help ; exit ${STATE_UNKNOWN}; fi
        ;;
        p)  PERFDATA="true"
            if [ "${DEBUG}" = "true" ]; then echo "Option p is set! sending Perfdata."; fi
        ;;
        v)  print_version
            exit ${STATE_OK};
        ;;
        h)  print_help
            exit ${STATE_OK};
        ;;
        :)  print_help
            exit ${STATE_UNKNOWN};
        ;;
        \?) print_help
            exit ${STATE_UNKNOWN};
        ;;
    esac
done


if [ "$TRESH_WARNING" = "" -a "$TRESH_CRITICAL" = "" ]; then
    echo "TEMP - UNKNOWN - unknown Parameter";
    print_help
    exit ${STATUS_UNKNOWN}
fi


#------------------------------------------------------------------------------
# Get temperature with digitemp
#------------------------------------------------------------------------------
DIGITEMP_OPTIONS="-a -s /dev/ttyUSB0 -r 750 -n 1 -q -o%.2C -c $HOME/.digitemprc"
TEMPERATURE=`$DIGITEMP $DIGITEMP_OPTIONS`
RTC=$?

### check result ###
DATE=`date +%Y%m%d-%H%M%S`
echo "$DATE - RTC: $RTC | TEMPERATURE: $TEMPERATURE" >>$HOME/check_digitemp_debug.log

echo $TEMPERATURE | egrep -q '^([-]?[0-9,:\.]+[ ]?)+$' || {
    echo "TEMP - UNKNOWN - Unknown value from sensor :$TEMPERATURE."
    exit $STATUS_UNKNOWN
}

#------------------------------------------------------------------------------
# compare with thresholds
#------------------------------------------------------------------------------
i=0
for temp in $TEMPERATURE; do
    if [ "${RESULT_TEMPERATURE}" = "" ]; then
        RESULT_TEMPERATURE="${i}:${temp}"
    else
        RESULT_TEMPERATURE="${RESULT_TEMPERATURE};${i}:${temp}"
    fi

    TRESH_WARNING_CHECK="${TRESH_WARNING:0:2}${TRESH_WARNING:3:4}"
    TRESH_CRITICAL_CHECK="${TRESH_CRITICAL:0:2}${TRESH_CRITICAL:3:4}"
    if [ "$(echo ${temp} | wc -m)" -eq "5" ]; then
        TEMPERATURE_CHECK="0${temp:0:1}${temp:2:3}"
    elif [ "$(echo ${temp} | wc -m)" -eq "6" ]; then
        TEMPERATURE_CHECK="${temp:0:2}${temp:3:4}"
    fi

    ### check warning state ###
    if [ ${TEMPERATURE_CHECK} -ge ${TRESH_WARNING_CHECK} ]; then
        if [ "${EXIT_STATUS}" = "" -o "${EXIT_STATUS}" = "0" -a \( "${EXIT_STATUS}" != "1" -o "${EXIT_STATUS}" != "2" \) ]; then
            RESULT="WARNING"
            EXIT_STATUS="${STATE_WARNING}"
        fi
    fi

    ### check critical state ###
    if [ ${TEMPERATURE_CHECK} -ge ${TRESH_CRITICAL_CHECK} ]; then
        if [ "${EXIT_STATUS}" = "" -o "${EXIT_STATUS}" = "0" -o "${EXIT_STATUS}" != "1" -a "${EXIT_STATUS}" != "2" ]; then
            RESULT="CRITICAL"
            EXIT_STATUS="${STATE_CRITICAL}"
        fi
    fi

    ### check ok state ###
    if [ ${TEMPERATURE_CHECK} -lt ${TRESH_CRITICAL_CHECK} ]; then
        if [ "${EXIT_STATUS}" = "" -a "${EXIT_STATUS}" != "0" -a "${EXIT_STATUS}" != "1" -a "${EXIT_STATUS}" != "2" ]; then
            RESULT="OK"
            EXIT_STATUS="${STATE_OK}"
        fi
    fi

    ### send perfdata if enabled ###
    if [ "$PERFDATA" = "true" ]; then
        RESULT_PERFDATA="${RESULT_PERFDATA}|'temp'=${i};${temp};${TRESH_WARNING};${TRESH_CRITICAL}"
    fi

    let i="${i}+1"
done

### send output and exit ###
echo "TEMP $RESULT - $RESULT_TEMPERATURE C $RESULT_PERFDATA"
exit $EXIT_STATUS
10-03-28_07-33-17_check_digitemp-1
