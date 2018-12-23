#!/bin/bash
#
# vbox-manage.sh
# 
# This script makes it easy to interact with VirtualBox's vboxmanage tool
#
# Requires: command vboxmanage grep sed readarray echo printf whereis cut date stat
#
# MIT License
#
# Copyright 2018 James Wilmoth
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
# associated documentation files (the "Software"), to deal in the Software without restriction, 
# including without limitation the rights to use, copy, modify, merge, publish, distribute, 
# sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or 
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
# OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Command set: {start pause resume reset acpipowerbutton poweroff savestate list}
# Target: 
# 	- reserved set: {* running saved off program copyright help}
#	- other: part of one or more VM names, or a single VM name, or a filename with VMs listed one per line
#
# ./vbox-manage.sh [command] [target]
#
# Examples:
#
#	./vbox-manage.sh start *			(this will start all VMs)
#	./vbox-manage.sh restart DC			(this would restart all VMs with 'DC' in the name)
#	./vbox-manage.sh pause MY-DC-001		(this would pause all VMs with 'MY-DC-001' in the name)
#	./vbox-manage.sh poweroff gameservers.txt	(this would power off all the VMs listed in the file)
#	./vbox-manage.sh acpipowerbutton GAME-SRV	(this is safer but possibly not supported by some VMs)
#	./vbox-manage.sh list *				(this would list all the VMs)
#	./vbox-manage.sh list running			(this would list all the VMs that are running)
#	./vbox-manage.sh list DC > DCs.txt		(this would list one or more VMs that have 'DC' in the name)
#
# Example crontab entry
#	0 * * * * /home/jwilmoth/vbox-manage.sh restart /home/jwilmoth/gameservers.txt
#
#   where jwilmoth is your own home folder and gameservers.txt is a file with one or more target VMs.
#
# NOTE: Targe is relative when used to specify a file. Be sure to use the full path unless it is local.
#

#####################################
# INITIALIZATION
#####################################

#Requirements
REQUIRED=("command vboxmanage" "grep" "sed" "readarray" "echo" "printf" "whereis" "cut" "date" "stat")
for req in "${REQUIRED[@]}"; do
	command -v $req &>null
	if [ "$?" -ne 0 ]; then
		echo "$req does not appear to be installed. Required: ${REQUIRED[@]}"
		exit $?
	fi	
done 

CACHEFILE="vbox-manage.tmp"
LOGFILE="vbox-manage.log"
LOGFILESIZE=$(stat -c%s "$LOGFILE")
MAXLOGFILESIZE=10000000
#Set variable (already tested for existence)
PROG="$(whereis VBoxManage | cut -d' ' -f2)"

#Log maintenance
if [ ! -f $CACHEFILE ]; then echo "" > $CACHEFILE; fi
if [ ! -f $LOGFILE ]; then echo "" > $LOGFILE; fi

if [ "$LOGFILESIZE" -gt $MAXLOGFILESIZE ]; then
	#Log to file
	DATE_WITH_TIME=`date "+%Y%m%d-%H%M%S"`
	echo "> $DATE_WITH_TIME | log file has exceeded 10MB; running cleanup" > $LOGFILE
fi

#####################################
# FUNCTIONS
#####################################

#Function to make code tidier
function log {
	DATE_WITH_TIME=`date "+%Y%m%d-%H%M%S"`
	LINE="> $DATE_WITH_TIME | $1"
	echo $LINE >> $LOGFILE
}

#Function to make code tidier
function print {
	DATE_WITH_TIME=`date "+%Y%m%d-%H%M%S"`
	LINE="> $DATE_WITH_TIME | $1"
	printf "$LINE\n"
}

#Function to make code tidier
function logAndPrint {
	DATE_WITH_TIME=`date "+%Y%m%d-%H%M%S"`
	LINE="> $DATE_WITH_TIME | $1"
	printf "$LINE\n"
	echo $LINE >> $LOGFILE
}

#Function to make code tidier AND bail
function logAndPrintFail {
	logAndPrint "$1"
	exit 1
}

#Function to handle vbox-manage.sh action
# handleAction [command] [target]
function handleAction {
	CMD="$1"
	TGT="$2"
	log "Command is $CMD..."
	case "$CMD" in
		("start")
			log "Processing $CMD on $TGT..."
			for vm in "${ALLVMS[@]}"; do
				log "Examining $vm..."
				if [[ "$vm" == *"${TGT[@]}"* ]]; then
					$PROG startvm "${vm[@]}" --type headless
				fi
			done; ;;
			#Old method before wildcard ability
			#$PROG startvm "${TGT[@]}" --type headless; ;;
		("pause" | "resume" | "reset"| "acpipowerbutton" | "poweroff" | "savestate")
			log "Processing $CMD on $TGT..."
			for vm in "${ALLVMS[@]}"; do
				if [[ "$vm" == *"${TGT[@]}"* ]]; then
					$PROG controlvm "${vm[@]}" "$CMD"
				fi
			done; ;;
			#Old method before wildcard ability
			#$PROG controlvm "${TGT[@]}" "$CMD"; ;;
		("list")			
			log "Processing $CMD on $TGT..."
			$PROG $CMD vms | grep "${TGT[@]}" | grep -o '".*"' | sed 's/"//g'; ;;
		*)
			logAndPrint "Command $CMD is not supported. Skipping $TGT..."; ;;
	esac
	
	if [ "$?" -ne 0 ]; then
		logAndPrintFail "An error was encountered. This command could not be completed as requested."
	fi
}

#####################################
# PROGRAM MAIN
#####################################

#Validate parameters
if [ "$#" -eq 2 ]; then
	log "Two parameter passed in OK"
	CMD="$1"
	TGT="$2"
else
	CMD="list"
	TGT="help"
fi

#Get list of all VMs
ALLVMS=()
$PROG list vms | grep -o '".*"' | sed 's/"//g' > $CACHEFILE
if [[ -f $CACHEFILE ]]; then
	readarray -t ALLVMS < $CACHEFILE 
fi
#DEBUG printf '%s\n' "${ARR[@]}"

#Get list of running VMs
RUNNINGVMS=()
$PROG list runningvms | grep -o '".*"' | sed 's/"//g' > $CACHEFILE
if [[ -f $CACHEFILE ]]; then
	readarray -t RUNNINGVMS < $CACHEFILE 
fi

#If target is a file, iterate over contents
if [[ -f $TGT ]]; then
	log "Target is a file..."
	FILEVMS=()
	readarray -t FILEVMS < $TGT 
	for vm in "${FILEVMS[@]}"; do
		log "Processing $vm"
		handleAction $CMD "$vm"
	done 
else
	log "Target is $TGT..."
	case "$TGT" in
		("*")
			for vm in "${ALLVMS[@]}"; do
				handleAction $CMD "$vm"
			done; ;;
		("running")
			for vm in "${RUNNINGVMS[@]}"; do				
				handleAction $CMD "$vm"
			done; ;;
		("saved" | "off")
			logAndPrint "Command $CMD is not supported. Skipping $TGT..."; ;;
		("program")
			more vbox-manage.sh; ;;
		("copyright")
			sed -n '9,26p' vbox-manage.sh; ;;
		("help")
			sed -n '28,44p' vbox-manage.sh; ;;
		*)
			handleAction $CMD "$TGT"
	esac
fi

exit 0
