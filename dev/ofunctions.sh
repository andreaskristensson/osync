#### MINIMAL-FUNCTION-SET BEGIN ####

## FUNC_BUILD=2016111505
## BEGIN Generic bash functions written in 2013-2016 by Orsiris de Jong - http://www.netpower.fr - ozy@netpower.fr

## To use in a program, define the following variables:
## PROGRAM=program-name
## INSTANCE_ID=program-instance-name
## _DEBUG=yes/no
## _LOGGER_STDERR=true/false
## _LOGGER_ERR_ONLY=true/false
## _LOGGER_PREFIX="date"/"time"/""

## Logger sets {ERROR|WARN}_ALERT variable when called with critical / error / warn loglevel
## When called from subprocesses, variable of main process can't be set. Status needs to be get via $RUN_DIR/$PROGRAM.Logger.{error|warn}.$SCRIPT_PID

#TODO: Windows checks, check sendmail & mailsend

if ! type "$BASH" > /dev/null; then
	echo "Please run this script only with bash shell. Tested on bash >= 3.2"
	exit 127
fi

## Correct output of sort command (language agnostic sorting)
export LC_ALL=C

# Standard alert mail body
MAIL_ALERT_MSG="Execution of $PROGRAM instance $INSTANCE_ID on $(date) has warnings/errors."

# Environment variables that can be overriden by programs
_DRYRUN=false
_SILENT=false
_VERBOSE=false
_LOGGER_PREFIX="date"
_LOGGER_STDERR=false
if [ "$KEEP_LOGGING" == "" ]; then
        KEEP_LOGGING=1801
fi

# Initial error status, logging 'WARN', 'ERROR' or 'CRITICAL' will enable alerts flags
ERROR_ALERT=false
WARN_ALERT=false

# Log from current run
CURRENT_LOG=""

## allow function call checks			#__WITH_PARANOIA_DEBUG
if [ "$_PARANOIA_DEBUG" == "yes" ];then		#__WITH_PARANOIA_DEBUG
	_DEBUG=yes				#__WITH_PARANOIA_DEBUG
fi						#__WITH_PARANOIA_DEBUG

## allow debugging from command line with _DEBUG=yes
if [ ! "$_DEBUG" == "yes" ]; then
	_DEBUG=no
	SLEEP_TIME=.05 # Tested under linux and FreeBSD bash, #TODO tests on cygwin / msys
	_VERBOSE=false
else
	if [ "$SLEEP_TIME" == "" ]; then
		SLEEP_TIME=1
	fi
	trap 'TrapError ${LINENO} $?' ERR
	_VERBOSE=true
fi

SCRIPT_PID=$$

LOCAL_USER=$(whoami)
LOCAL_HOST=$(hostname)

if [ "$PROGRAM" == "" ]; then
	PROGRAM="ofunctions"
fi

## Default log file until config file is loaded
if [ -w /var/log ]; then
	LOG_FILE="/var/log/$PROGRAM.log"
elif ([ "$HOME" != "" ] && [ -w "$HOME" ]); then
	LOG_FILE="$HOME/$PROGRAM.log"
else
	LOG_FILE="./$PROGRAM.log"
fi

## Default directory where to store temporary run files
if [ -w /tmp ]; then
	RUN_DIR=/tmp
elif [ -w /var/tmp ]; then
	RUN_DIR=/var/tmp
else
	RUN_DIR=.
fi


# Default alert attachment filename
ALERT_LOG_FILE="$RUN_DIR/$PROGRAM.$SCRIPT_PID.last.log"

# Set error exit code if a piped command fails
	set -o pipefail
	set -o errtrace


function Dummy {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	sleep $SLEEP_TIME
}

# Sub function of Logger
function _Logger {
	local svalue="${1}" # What to log to stdout
	local lvalue="${2:-$svalue}" # What to log to logfile, defaults to screen value
	local evalue="${3}" # What to log to stderr

	echo -e "$lvalue" >> "$LOG_FILE"
	CURRENT_LOG="$CURRENT_LOG"$'\n'"$lvalue"

	if [ $_LOGGER_STDERR == true ] && [ "$evalue" != "" ]; then
		cat <<< "$evalue" 1>&2
	elif [ "$_SILENT" == false ]; then
		echo -e "$svalue"
	fi
}

# General log function with log levels:
# CRITICAL, ERROR, WARN are colored in stdout, prefixed in stderr
# NOTICE is standard level
# VERBOSE is only sent to stdout / stderr if _VERBOSE=true
# DEBUG & PARANOIA_DEBUG are only sent if _DEBUG=yes
function Logger {
	local value="${1}" # Sentence to log (in double quotes)
	local level="${2}" # Log level: PARANOIA_DEBUG, DEBUG, VERBOSE, NOTICE, WARN, ERROR, CRITIAL

	if [ "$_LOGGER_PREFIX" == "time" ]; then
		prefix="TIME: $SECONDS - "
	elif [ "$_LOGGER_PREFIX" == "date" ]; then
		prefix="$(date) - "
	else
		prefix=""
	fi

	if [ "$level" == "CRITICAL" ]; then
		_Logger "$prefix\e[41m$value\e[0m" "$prefix$level:$value" "$level:$value"
		ERROR_ALERT=true
		# ERROR_ALERT / WARN_ALERT isn't set in main when Logger is called from a subprocess. Need to keep this flag.
		echo "1" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.error.$SCRIPT_PID"
		return
	elif [ "$level" == "ERROR" ]; then
		_Logger "$prefix\e[91m$value\e[0m" "$prefix$level:$value" "$level:$value"
		ERROR_ALERT=true
		echo "1" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.error.$SCRIPT_PID"
		return
	elif [ "$level" == "WARN" ]; then
		_Logger "$prefix\e[33m$value\e[0m" "$prefix$level:$value" "$level:$value"
		WARN_ALERT=true
		echo "1" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.warn.$SCRIPT_PID"
		return
	elif [ "$level" == "NOTICE" ]; then
		if [ "$_LOGGER_ERR_ONLY" != true ]; then
			_Logger "$prefix$value"
		fi
		return
	elif [ "$level" == "VERBOSE" ]; then
		if [ $_VERBOSE == true ]; then
			_Logger "$prefix$value"
		fi
		return
	elif [ "$level" == "ALWAYS" ]; then
		if [ $_SILENT != true ]; then
			_Logger "$prefix$value" "$prefix$level:$value" "$level:$value"
		fi
		return
	elif [ "$level" == "DEBUG" ]; then
		if [ "$_DEBUG" == "yes" ]; then
			_Logger "$prefix$value"
			return
		fi
	elif [ "$level" == "PARANOIA_DEBUG" ]; then		#__WITH_PARANOIA_DEBUG
		if [ "$_PARANOIA_DEBUG" == "yes" ]; then	#__WITH_PARANOIA_DEBUG
			_Logger "$prefix$value"			#__WITH_PARANOIA_DEBUG
			return					#__WITH_PARANOIA_DEBUG
		fi						#__WITH_PARANOIA_DEBUG
	else
		_Logger "\e[41mLogger function called without proper loglevel [$level].\e[0m"
		_Logger "Value was: $prefix$value"
	fi
}

# QuickLogger subfunction, can be called directly
function _QuickLogger {
	local value="${1}"
	local destination="${2}" # Destination: stdout, log, both

	__CheckArguments 2 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	if ([ "$destination" == "log" ] || [ "$destination" == "both" ]); then
		echo -e "$(date) - $value" >> "$LOG_FILE"
	elif ([ "$destination" == "stdout" ] || [ "$destination" == "both" ]); then
		echo -e "$value"
	fi
}

# Generic quick logging function
function QuickLogger {
	local value="${1}"

	__CheckArguments 1 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	if [ $_SILENT == true ]; then
		_QuickLogger "$value" "log"
	else
		_QuickLogger "$value" "stdout"
	fi
}

# Portable child (and grandchild) kill function tester under Linux, BSD and MacOS X
function KillChilds {
	local pid="${1}" # Parent pid to kill childs
	local self="${2:-false}" # Should parent be killed too ?


	if children="$(pgrep -P "$pid")"; then
		for child in $children; do
			Logger "Launching KillChilds \"$child\" true" "DEBUG"	#__WITH_PARANOIA_DEBUG
			KillChilds "$child" true
		done
	fi
		# Try to kill nicely, if not, wait 15 seconds to let Trap actions happen before killing
	if ( [ "$self" == true ] && kill -0 $pid > /dev/null 2>&1); then
		Logger "Sending SIGTERM to process [$pid]." "DEBUG"
		kill -s TERM "$pid"
		if [ $? != 0 ]; then
			sleep 15
			Logger "Sending SIGTERM to process [$pid] failed." "DEBUG"
			kill -9 "$pid"
			if [ $? != 0 ]; then
				Logger "Sending SIGKILL to process [$pid] failed." "DEBUG"
				return 1
			fi
		else
			return 0
		fi
	else
		return 0
	fi
}

function KillAllChilds {
	local pids="${1}" # List of parent pids to kill separated by semi-colon
	local self="${2:-false}" # Should parent be killed too ?

	__CheckArguments 1 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local errorcount=0

	IFS=';' read -a pidsArray <<< "$pids"
	for pid in "${pidsArray[@]}"; do
		KillChilds $pid $self
		if [ $? != 0 ]; then
			errorcount=$((errorcount+1))
			fi
	done
	return $errorcount
}

# osync/obackup/pmocr script specific mail alert function, use SendEmail function for generic mail sending
function SendAlert {
	local runAlert="${1:-false}" # Specifies if current message is sent while running or at the end of a run

	__CheckArguments 0-1 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local attachment=
	local attachmentFile=
	local subject=
	local body=

	if [ "$DESTINATION_MAILS" == "" ]; then
		return 0
	fi

	if [ "$_DEBUG" == "yes" ]; then
		Logger "Debug mode, no warning mail will be sent." "NOTICE"
		return 0
	fi

	# <OSYNC SPECIFIC>
	if [ "$_QUICK_SYNC" == "2" ]; then
		Logger "Current task is a quicksync task. Will not send any alert." "NOTICE"
		return 0
	fi
	# </OSYNC SPECIFIC>

	eval "cat \"$LOG_FILE\" $COMPRESSION_PROGRAM > $ALERT_LOG_FILE"
	if [ $? != 0 ]; then
		Logger "Cannot create [$ALERT_LOG_FILE]" "WARN"
		attachment=false
	else
		attachment=true
	fi
	body="$MAIL_ALERT_MSG"$'\n\n'"$CURRENT_LOG"

	if [ $ERROR_ALERT == true ]; then
		subject="Error alert for $INSTANCE_ID"
	elif [ $WARN_ALERT == true ]; then
		subject="Warning alert for $INSTANCE_ID"
	else
		subject="Alert for $INSTANCE_ID"
	fi

	if [ $runAlert == true ]; then
		subject="Currently runing - $subject"
	else
		subject="Fnished run - $subject"
	fi

	if [ "$attachment" == true ]; then
		attachmentFile="$ALERT_LOG_FILE"
	fi

	SendEmail "$subject" "$body" "$DESTINATION_MAILS" "$attachmentFile" "$SENDER_MAIL" "$SMTP_SERVER" "$SMTP_PORT" "$ENCRYPTION" "SMTP_USER" "$SMTP_PASSWORD"

	# Delete tmp log file
	if [ "$attachment" == true ]; then
		if [ -f "$ALERT_LOG_FILE" ]; then
			rm -f "$ALERT_LOG_FILE"
		fi
	fi
}

# Generic email sending function.
# Usage (linux / BSD), attachment is optional, can be "/path/to/my.file" or ""
# SendEmail "subject" "Body text" "receiver@example.com receiver2@otherdomain.com" "/path/to/attachment.file"
# Usage (Windows, make sure you have mailsend.exe in executable path, see http://github.com/muquit/mailsend)
# attachment is optional but must be in windows format like "c:\\some\path\\my.file", or ""
# smtp_server.domain.tld is mandatory, as is smtpPort (should be 25, 465 or 587)
# encryption can be set to tls, ssl or none
# smtpUser and smtpPassword are optional
# SendEmail "subject" "Body text" "receiver@example.com receiver2@otherdomain.com" "/path/to/attachment.file" "senderMail@example.com" "smtpServer.domain.tld" "smtpPort" "encryption" "smtpUser" "smtpPassword"
function SendEmail {
	local subject="${1}"
	local message="${2}"
	local destinationMails="${3}"
	local attachment="${4}"
	local senderMail="${5}"
	local smtpServer="${6}"
	local smtpPort="${7}"
	local encryption="${8}"
	local smtpUser="${9}"
	local smtpPassword="${10}"

	# CheckArguments will report a warning that can be ignored if used in Windows with paranoia debug enabled
	__CheckArguments 4 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local mail_no_attachment=
	local attachment_command=

	local encryption_string=
	local auth_string=

	if [ ! -f "$attachment" ]; then
		attachment_command="-a $attachment"
		mail_no_attachment=1
	else
		mail_no_attachment=0
	fi

	if [ "$LOCAL_OS" == "BUSYBOX" ]; then
		if type sendmail > /dev/null 2>&1; then
			if [ "$ENCRYPTION" == "tls" ]; then
				echo -e "Subject:$subject\r\n$message" | $(type -p sendmail) -f "$SenderMail" -H "exec openssl s_client -quiet -tls1_2 -starttls smtp -connect $smtpServer:$smtpPort" -au"$smtpUser" -ap"$smtpPassword" "$destinationMails"
			elif [ "$ENCRYPTION" == "ssl" ]; then
				echo -e "Subject:$subject\r\n$message" | $(type -p sendmail) -f "$SenderMail" -H "exec openssl s_client -quiet -connect $smtpServer:$smtpPort" -au"$smtpUser" -ap"$smtpPassword" "$destinationMails"
			else
				echo -e "Subject:$subject\r\n$message" | $(type -p sendmail) -f "$SenderMail" -S "$smtpServer:$SmtpPort" -au"$smtpUser" -ap"$smtpPassword" "$destinationMails"
			fi

			if [ $? != 0 ]; then
				Logger "Cannot send alert mail via $(type -p sendmail) !!!" "WARN"
				# Don't bother try other mail systems with busybox
				return 1
			else
				return 0
			fi
		else
			Logger "Sendmail not present. Won't send any mail" "WARN"
			return 1
		fi
	fi

	if type mutt > /dev/null 2>&1 ; then
		echo "$message" | $(type -p mutt) -x -s "$subject" "$destinationMails" $attachment_command
		if [ $? != 0 ]; then
			Logger "Cannot send mail via $(type -p mutt) !!!" "WARN"
		else
			Logger "Sent mail using mutt." "NOTICE"
			return 0
		fi
	fi

	if type mail > /dev/null 2>&1 ; then
		if [ "$mail_no_attachment" -eq 0 ] && $(type -p mail) -V | grep "GNU" > /dev/null; then
			attachment_command="-A $attachment"
		elif [ "$mail_no_attachment" -eq 0 ] && $(type -p mail) -V > /dev/null; then
			attachment_command="-a$attachment"
		else
			attachment_command=""
		fi
		echo "$message" | $(type -p mail) $attachment_command -s "$subject" "$destinationMails"
		if [ $? != 0 ]; then
			Logger "Cannot send mail via $(type -p mail) with attachments !!!" "WARN"
			echo "$message" | $(type -p mail) -s "$subject" "$destinationMails"
			if [ $? != 0 ]; then
				Logger "Cannot send mail via $(type -p mail) without attachments !!!" "WARN"
			else
				Logger "Sent mail using mail command without attachment." "NOTICE"
				return 0
			fi
		else
			Logger "Sent mail using mail command." "NOTICE"
			return 0
		fi
	fi

	if type sendmail > /dev/null 2>&1 ; then
		echo -e "Subject:$subject\r\n$message" | $(type -p sendmail) "$destinationMails"
		if [ $? != 0 ]; then
			Logger "Cannot send mail via $(type -p sendmail) !!!" "WARN"
		else
			Logger "Sent mail using sendmail command without attachment." "NOTICE"
			return 0
		fi
	fi

	# Windows specific
	if type "mailsend.exe" > /dev/null 2>&1 ; then
		if [ "$senderMail" == "" ]; then
			Logger "Missing sender email." "ERROR"
			return 1
		fi
		if [ "$smtpServer" == "" ]; then
			Logger "Missing smtp port." "ERROR"
			return 1
		fi
		if [ "$smtpPort" == "" ]; then
			Logger "Missing smtp port, assuming 25." "WARN"
			smtpPort=25
		fi
		if [ "$encryption" != "tls" ] && [ "$encryption" != "ssl" ]  && [ "$encryption" != "none" ]; then
			Logger "Bogus smtp encryption, assuming none." "WARN"
			encryption_string=
		elif [ "$encryption" == "tls" ]; then
			encryption_string=-starttls
		elif [ "$encryption" == "ssl" ]:; then
			encryption_string=-ssl
		fi
		if [ "$smtpUser" != "" ] && [ "$smtpPassword" != "" ]; then
			auth_string="-auth -user \"$smtpUser\" -pass \"$smtpPassword\""
		fi
		$(type mailsend.exe) -f "$senderMail" -t "$destinationMails" -sub "$subject" -M "$message" -attach "$attachment" -smtp "$smtpServer" -port "$smtpPort" $encryption_string $auth_string
		if [ $? != 0 ]; then
			Logger "Cannot send mail via $(type mailsend.exe) !!!" "WARN"
		else
			Logger "Sent mail using mailsend.exe command with attachment." "NOTICE"
			return 0
		fi
	fi

	# pfSense specific
	if [ -f /usr/local/bin/mail.php ]; then
		echo "$message" | /usr/local/bin/mail.php -s="$subject"
		if [ $? != 0 ]; then
			Logger "Cannot send mail via /usr/local/bin/mail.php (pfsense) !!!" "WARN"
		else
			Logger "Sent mail using pfSense mail.php." "NOTICE"
			return 0
		fi
	fi

	# If function has not returned 0 yet, assume it is critical that no alert can be sent
	Logger "Cannot send mail (neither mutt, mail, sendmail, sendemail, mailsend (windows) or pfSense mail.php could be used)." "ERROR" # Is not marked critical because execution must continue
}

function TrapError {
	local job="$0"
	local line="$1"
	local code="${2:-1}"

	if [ $_SILENT == false ]; then
		echo -e "\e[45m/!\ ERROR in ${job}: Near line ${line}, exit code ${code}\e[0m"
	fi
}

function LoadConfigFile {
	local configFile="${1}"

	__CheckArguments 1 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG


	if [ ! -f "$configFile" ]; then
		Logger "Cannot load configuration file [$configFile]. Cannot start." "CRITICAL"
		exit 1
	elif [[ "$configFile" != *".conf" ]]; then
		Logger "Wrong configuration file supplied [$configFile]. Cannot start." "CRITICAL"
		exit 1
	else
		# Remove everything that is not a variable assignation
		grep '^[^ ]*=[^;&]*' "$configFile" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID"
		source "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID"
	fi

	CONFIG_FILE="$configFile"
}

function Spinner {
	if [ $_SILENT == true ] || [ "$_LOGGER_ERR_ONLY" == true ]; then
		return 0
	fi

	case $toggle
	in
	1)
	echo -n " \ "
	echo -ne "\r"
	toggle="2"
	;;

	2)
	echo -n " | "
	echo -ne "\r"
	toggle="3"
	;;

	3)
	echo -n " / "
	echo -ne "\r"
	toggle="4"
	;;

	*)
	echo -n " - "
	echo -ne "\r"
	toggle="1"
	;;
	esac
}

# Array to string converter, see http://stackoverflow.com/questions/1527049/bash-join-elements-of-an-array
# usage: joinString separaratorChar Array
function joinString {
	local IFS="$1"; shift; echo "$*";
}

# Time control function for background processes, suitable for multiple synchronous processes
# Fills a global variable called WAIT_FOR_TASK_COMPLETION that contains list of failed pids in format pid1:result1;pid2:result2
# Warning: Don't imbricate this function into another run if you plan to use the global variable output

function WaitForTaskCompletion {
	local pids="${1}" # pids to wait for, separated by semi-colon
	local softMaxTime="${2}" # If program with pid $pid takes longer than $softMaxTime seconds, will log a warning, unless $softMaxTime equals 0.
	local hardMaxTime="${3}" # If program with pid $pid takes longer than $hardMaxTime seconds, will stop execution, unless $hardMaxTime equals 0.
	local callerName="${4}" # Who called this function
	local counting="${5:-true}" # Count time since function has been launched if true, since script has been launched if false
	local keepLogging="${6:-0}" # Log a standby message every X seconds. Set to zero to disable logging

	Logger "${FUNCNAME[0]} called by [$callerName]." "PARANOIA_DEBUG"	#__WITH_PARANOIA_DEBUG
	__CheckArguments 6 $# ${FUNCNAME[0]} "$@"				#__WITH_PARANOIA_DEBUG

	local soft_alert=false # Does a soft alert need to be triggered, if yes, send an alert once
	local log_ttime=0 # local time instance for comparaison

	local seconds_begin=$SECONDS # Seconds since the beginning of the script
	local exec_time=0 # Seconds since the beginning of this function

	local retval=0 # return value of monitored pid process
	local errorcount=0 # Number of pids that finished with errors

	local pid	# Current pid working on
	local pidCount # number of given pids
	local pidState # State of the process

	local pidsArray # Array of currently running pids
	local newPidsArray # New array of currently running pids

	local hasPids=false # Are any valable pids given to function ?		#__WITH_PARANOIA_DEBUG

	IFS=';' read -a pidsArray <<< "$pids"
	pidCount=${#pidsArray[@]}

	WAIT_FOR_TASK_COMPLETION=""

	while [ ${#pidsArray[@]} -gt 0 ]; do
		newPidsArray=()

		Spinner
		if [ $counting == true ]; then
			exec_time=$(($SECONDS - $seconds_begin))
		else
			exec_time=$SECONDS
		fi

		if [ $keepLogging -ne 0 ]; then
			if [ $((($exec_time + 1) % $keepLogging)) -eq 0 ]; then
				if [ $log_ttime -ne $exec_time ]; then # Fix when sleep time lower than 1s
					log_ttime=$exec_time
					Logger "Current tasks still running with pids [$(joinString , ${pidsArray[@]})]." "NOTICE"
				fi
			fi
		fi

		if [ $exec_time -gt $softMaxTime ]; then
			if [ $soft_alert == true ] && [ $softMaxTime -ne 0 ]; then
				Logger "Max soft execution time exceeded for task [$callerName] with pids [$(joinString , ${pidsArray[@]})]." "WARN"
				soft_alert=true
				SendAlert true

			fi
			if [ $exec_time -gt $hardMaxTime ] && [ $hardMaxTime -ne 0 ]; then
				Logger "Max hard execution time exceeded for task [$callerName] with pids [$(joinString , ${pidsArray[@]})]. Stopping task execution." "ERROR"
				for pid in "${pidsArray[@]}"; do
					KillChilds $pid true
					if [ $? == 0 ]; then
						Logger "Task with pid [$pid] stopped successfully." "NOTICE"
					else
						Logger "Could not stop task with pid [$pid]." "ERROR"
					fi
				done
				SendAlert true
			fi
		fi

		for pid in "${pidsArray[@]}"; do
			if [ $(IsInteger $pid) -eq 1 ]; then
				if kill -0 $pid > /dev/null 2>&1; then
					# Handle uninterruptible sleep state or zombies by ommiting them from running process array (How to kill that is already dead ? :)
					#TODO(high): have this tested on *BSD, Mac, Win & busybox.
					#TODO(high): propagate changes to ParallelExec
					#pidState=$(ps -p$pid -o state= 2 > /dev/null)
					pidState="$(eval $PROCESS_STATE_CMD)"
					if [ "$pidState" != "D" ] && [ "$pidState" != "Z" ]; then
						newPidsArray+=($pid)
					fi
				else
					# pid is dead, get it's exit code from wait command
					wait $pid
					retval=$?
					if [ $retval -ne 0 ]; then
						errorcount=$((errorcount+1))
						Logger "${FUNCNAME[0]} called by [$callerName] finished monitoring [$pid] with exitcode [$retval]." "DEBUG"
						if [ "$WAIT_FOR_TASK_COMPLETION" == "" ]; then
							WAIT_FOR_TASK_COMPLETION="$pid:$retval"
						else
							WAIT_FOR_TASK_COMPLETION=";$pid:$retval"
						fi
					fi
				fi
				hasPids=true					##__WITH_PARANOIA_DEBUG
			fi
		done

		if [ $hasPids == false ]; then					##__WITH_PARANOIA_DEBUG
			Logger "No valable pids given." "ERROR" 		##__WITH_PARANOIA_DEBUG
		fi								##__WITH_PARANOIA_DEBUG

		pidsArray=("${newPidsArray[@]}")
		# Trivial wait time for bash to not eat up all CPU
		sleep $SLEEP_TIME
	done

	Logger "${FUNCNAME[0]} ended for [$callerName] using [$pidCount] subprocesses with [$errorcount] errors." "PARANOIA_DEBUG"	#__WITH_PARANOIA_DEBUG

	# Return exit code if only one process was monitored, else return number of errors
	if [ $pidCount -eq 1 ] && [ $errorcount -eq 0 ]; then
		return $errorcount
	else
		return $errorcount
	fi
}

# Take a list of commands to run, runs them sequentially with numberOfProcesses commands simultaneously runs
# Returns the number of non zero exit codes from commands
# Use cmd1;cmd2;cmd3 syntax for small sets, use file for large command sets
function ParallelExec {
	local numberOfProcesses="${1}" # Number of simultaneous commands to run
	local commandsArg="${2}" # Semi-colon separated list of commands, or file containing one command per line
	local readFromFile="${3:-false}" # Is commandsArg a file or a string ?
	local softMaxTime="${4:-0}"
	local hardMaxTime="${5:-0}"
	local callerName="${6}" # Who called this function
	local counting="${7:-true}" # Count time since function has been launched if true, since script has been launched if false
	local keepLogging="${8:-0}" # Log a standby message every X seconds. Set to zero to disable logging

	__CheckArguments 8 $# ${FUNCNAME[0]} "$@"				#__WITH_PARANOIA_DEBUG

	local commandCount
	local command
	local pid
	local counter=0
	local commandsArray
	local pidsArray
	local newPidsArray
	local retval
	local errorCount=0
	local pidState
	local commandsArrayPid

	local hasPids=false # Are any valable pids given to function ?		#__WITH_PARANOIA_DEBUG

	if [ $readFromFile == true ];then
		if [ -f "$commandsArg" ]; then
			commandCount=$(wc -l < "$commandsArg")
		else
			commandCount=0
		fi
	else
		IFS=';' read -r -a commandsArray <<< "$commandsArg"
		commandCount=${#commandsArray[@]}
	fi

	Logger "Runnning $commandCount commands in $numberOfProcesses simultaneous processes." "DEBUG"

	while [ $counter -lt "$commandCount" ] || [ ${#pidsArray[@]} -gt 0 ]; do

		while [ $counter -lt "$commandCount" ] && [ ${#pidsArray[@]} -lt $numberOfProcesses ]; do
			if [ $readFromFile == true ]; then
				#TODO: Checked on FreeBSD 10, also check on Win
				command=$(awk 'NR == num_line {print; exit}' num_line=$((counter+1)) "$commandsArg")
			else
				command="${commandsArray[$counter]}"
			fi
			Logger "Running command [$command]." "DEBUG"
			eval "$command" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID" 2>&1 &
			pid=$!
			pidsArray+=($pid)
			commandsArrayPid[$pid]="$command"
			counter=$((counter+1))
		done


		newPidsArray=()
		for pid in "${pidsArray[@]}"; do
			if [ $(IsInteger $pid) -eq 1 ]; then
				# Handle uninterruptible sleep state or zombies by ommiting them from running process array (How to kill that is already dead ? :)
				if kill -0 $pid > /dev/null 2>&1; then
					#pidState=$(ps -p$pid -o state= 2 > /dev/null)
					pidState="$(eval $PROCESS_STATE_CMD)"
					if [ "$pidState" != "D" ] && [ "$pidState" != "Z" ]; then
						newPidsArray+=($pid)
					fi
				else
					# pid is dead, get it's exit code from wait command
					wait $pid
					retval=$?
					if [ $retval -ne 0 ]; then
						Logger "Command [${commandsArrayPid[$pid]}] failed with exit code [$retval]." "ERROR"
						errorCount=$((errorCount+1))
					fi
				fi
				hasPids=true					##__WITH_PARANOIA_DEBUG
			fi
		done

		if [ $hasPids == false ]; then					##__WITH_PARANOIA_DEBUG
			Logger "No valable pids given." "ERROR"			##__WITH_PARANOIA_DEBUG
		fi								##__WITH_PARANOIA_DEBUG
		pidsArray=("${newPidsArray[@]}")

		# Trivial wait time for bash to not eat up all CPU
		sleep $SLEEP_TIME
	done

	return $errorCount
}

function CleanUp {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	if [ "$_DEBUG" != "yes" ]; then
		rm -f "$RUN_DIR/$PROGRAM."*".$SCRIPT_PID"
		# Fix for sed -i requiring backup extension for BSD & Mac (see all sed -i statements)
		rm -f "$RUN_DIR/$PROGRAM."*".$SCRIPT_PID.tmp"
	fi
}

# obsolete, use StripQuotes
function SedStripQuotes {
	echo $(echo $1 | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")
}

# Usage: var=$(StripSingleQuotes "$var")
function StripSingleQuotes {
	local string="${1}"

	string="${string/#\'/}" # Remove singlequote if it begins string
	string="${string/%\'/}" # Remove singlequote if it ends string
	echo "$string"
}

# Usage: var=$(StripDoubleQuotes "$var")
function StripDoubleQuotes {
	local string="${1}"

	string="${string/#\"/}"
	string="${string/%\"/}"
	echo "$string"
}

function StripQuotes {
	local string="${1}"

	echo "$(StripSingleQuotes $(StripDoubleQuotes $string))"
}

# Usage var=$(EscapeSpaces "$var") or var="$(EscapeSpaces "$var")"
function EscapeSpaces {
	local string="${1}" # String on which spaces will be escaped

	echo "${string// /\\ }"
}

function IsNumericExpand {
	eval "local value=\"${1}\"" # Needed eval so variable variables can be processed

	local re="^-?[0-9]+([.][0-9]+)?$"

	if [[ $value =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
		echo 1
	else
		echo 0
	fi
}

# Usage [ $(IsNumeric $var) -eq 1 ]
function IsNumeric {
	local value="${1}"

	if [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]]; then
		echo 1
	else
		echo 0
	fi
}

function IsInteger {
	local value="${1}"

	if [[ $value =~ ^[0-9]+$ ]]; then
		echo 1
	else
		echo 0
	fi
}

# Converts human readable sizes into integer kilobyte sizes
# Usage numericSize="$(HumanToNumeric $humanSize)"
function HumanToNumeric {
	local value="${1}"

	local notation
	local suffix
	local suffixPresent
	local multiplier

	notation=(K M G T P E)
	for suffix in "${notation[@]}"; do
		multiplier=$((multiplier+1))
		if [[ "$value" == *"$suffix"* ]]; then
			suffixPresent=$suffix
			break;
		fi
	done

	if [ "$suffixPresent" != "" ]; then
		value=${value%$suffix*}
		value=${value%.*}
		# /1024 since we convert to kilobytes instead of bytes
		value=$((value*(1024**multiplier/1024)))
	else
		value=${value%.*}
	fi

	echo $value
}

## from https://gist.github.com/cdown/1163649
function urlEncode {
	local length="${#1}"

	local LANG=C
	for (( i = 0; i < length; i++ )); do
		local c="${1:i:1}"
		case $c in
			[a-zA-Z0-9.~_-])
			printf "$c"
			;;
			*)
			printf '%%%02X' "'$c"
			;;
		esac
	done
}

function urlDecode {
	local urlEncoded="${1//+/ }"

	printf '%b' "${urlEncoded//%/\\x}"
}

## Modified version of http://stackoverflow.com/a/8574392
## Usage: arrayContains "needle" "${haystack[@]}"
arrayContains () {
	local e

	if [ "$2" == "" ]; then
		echo 0 && return 0
	fi

	for e in "${@:2}"; do
		[[ "$e" == "$1" ]] && echo 1 && return 1
	done
	echo 0 && return 0
}

function GetLocalOS {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local localOsVar

	# There's no good way to tell if currently running in BusyBox shell. Using sluggish way.
	if ls --help 2>&1 | grep -i "BusyBox" > /dev/null; then
		localOsVar="BusyBox"
	else
		localOsVar="$(uname -spio 2>&1)"
		if [ $? != 0 ]; then
			localOsVar="$(uname -v 2>&1)"
			if [ $? != 0 ]; then
				localOsVar="$(uname)"
			fi
		fi
	fi

	case $localOsVar in
		*"Linux"*)
		LOCAL_OS="Linux"
		;;
		*"BSD"*)
		LOCAL_OS="BSD"
		;;
		*"MINGW32"*|*"CYGWIN"*)
		LOCAL_OS="msys"
		;;
		*"Darwin"*)
		LOCAL_OS="MacOSX"
		;;
		*"BusyBox"*)
		LOCAL_OS="BUSYBOX"
		;;
		*)
		if [ "$IGNORE_OS_TYPE" == "yes" ]; then		#TODO(doc): Undocumented option
			Logger "Running on unknown local OS [$localOsVar]." "WARN"
			return
		fi
		Logger "Running on >> $localOsVar << not supported. Please report to the author." "ERROR"
		exit 1
		;;
	esac
	Logger "Local OS: [$localOsVar]." "DEBUG"
}

#### MINIMAL-FUNCTION-SET END ####

function GetRemoteOS {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local remoteOsVar

$SSH_CMD bash -s << 'ENDSSH' >> "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID" 2>&1

function GetOs {
	local localOsVar

	# There's no good way to tell if currently running in BusyBox shell. Using sluggish way.
	if ls --help 2>&1 | grep -i "BusyBox" > /dev/null; then
		localOsVar="BusyBox"
	else
		localOsVar="$(uname -spio 2>&1)"
		if [ $? != 0 ]; then
			localOsVar="$(uname -v 2>&1)"
			if [ $? != 0 ]; then
				localOsVar="$(uname)"
			fi
		fi
	fi

	echo "$localOsVar"
}

GetOs

ENDSSH

	if [ -f "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID" ]; then
		remoteOsVar=$(cat "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID")
		case $remoteOsVar in
			*"Linux"*)
			REMOTE_OS="Linux"
			;;
			*"BSD"*)
			REMOTE_OS="BSD"
			;;
			*"MINGW32"*|*"CYGWIN"*)
			REMOTE_OS="msys"
			;;
			*"Darwin"*)
			REMOTE_OS="MacOSX"
			;;
			*"BusyBox"*)
			REMOTE_OS="BUSYBOX"
			;;
			*"ssh"*|*"SSH"*)
			Logger "Cannot connect to remote system." "CRITICAL"
			exit 1
			;;
			*)
			if [ "$IGNORE_OS_TYPE" == "yes" ]; then		#DOC: Undocumented debug only setting
				Logger "Running on unknown remote OS [$remoteOsVar]." "WARN"
				return
			fi
			Logger "Running on remote OS failed. Please report to the author if the OS is not supported." "CRITICAL"
			Logger "Remote OS said:\n$remoteOsVar" "CRITICAL"
			exit 1
		esac
		Logger "Remote OS: [$remoteOsVar]." "DEBUG"
	else
		Logger "Cannot get Remote OS" "CRITICAL"
	fi
}

function RunLocalCommand {
	local command="${1}" # Command to run
	local hardMaxTime="${2}" # Max time to wait for command to compleet
	__CheckArguments 2 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	if [ $_DRYRUN == true ]; then
		Logger "Dryrun: Local command [$command] not run." "NOTICE"
		return 0
	fi

	Logger "Running command [$command] on local host." "NOTICE"
	eval "$command" > "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID" 2>&1 &
	WaitForTaskCompletion $! 0 $hardMaxTime ${FUNCNAME[0]} true $KEEP_LOGGING
	retval=$?
	if [ $retval -eq 0 ]; then
		Logger "Command succeded." "NOTICE"
	else
		Logger "Command failed." "ERROR"
	fi

	if [ $_VERBOSE == true ] || [ $retval -ne 0 ]; then
		Logger "Command output:\n$(cat $RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID)" "NOTICE"
	fi

	if [ "$STOP_ON_CMD_ERROR" == "yes" ] && [ $retval -ne 0 ]; then
		Logger "Stopping on command execution error." "CRITICAL"
		exit 1
	fi
}

## Runs remote command $1 and waits for completition in $2 seconds
function RunRemoteCommand {
	local command="${1}" # Command to run
	local hardMaxTime="${2}" # Max time to wait for command to compleet
	__CheckArguments 2 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	CheckConnectivity3rdPartyHosts
	CheckConnectivityRemoteHost
	if [ $_DRYRUN == true ]; then
		Logger "Dryrun: Local command [$command] not run." "NOTICE"
		return 0
	fi

	Logger "Running command [$command] on remote host." "NOTICE"
	cmd=$SSH_CMD' "$command" > "'$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID'" 2>&1'
	Logger "cmd: $cmd" "DEBUG"
	eval "$cmd" &
	WaitForTaskCompletion $! 0 $hardMaxTime ${FUNCNAME[0]} true $KEEP_LOGGING
	retval=$?
	if [ $retval -eq 0 ]; then
		Logger "Command succeded." "NOTICE"
	else
		Logger "Command failed." "ERROR"
	fi

	if [ -f "$RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID" ] && ([ $_VERBOSE == true ] || [ $retval -ne 0 ])
	then
		Logger "Command output:\n$(cat $RUN_DIR/$PROGRAM.${FUNCNAME[0]}.$SCRIPT_PID)" "NOTICE"
	fi

	if [ "$STOP_ON_CMD_ERROR" == "yes" ] && [ $retval -ne 0 ]; then
		Logger "Stopping on command execution error." "CRITICAL"
		exit 1
	fi
}

function RunBeforeHook {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local pids

	if [ "$LOCAL_RUN_BEFORE_CMD" != "" ]; then
		RunLocalCommand "$LOCAL_RUN_BEFORE_CMD" $MAX_EXEC_TIME_PER_CMD_BEFORE &
		pids="$!"
	fi

	if [ "$REMOTE_RUN_BEFORE_CMD" != "" ]; then
		RunRemoteCommand "$REMOTE_RUN_BEFORE_CMD" $MAX_EXEC_TIME_PER_CMD_BEFORE &
		pids="$pids;$!"
	fi
	if [ "$pids" != "" ]; then
		WaitForTaskCompletion $pids 0 0 ${FUNCNAME[0]} true $KEEP_LOGGING
	fi
}

function RunAfterHook {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local pids

	if [ "$LOCAL_RUN_AFTER_CMD" != "" ]; then
		RunLocalCommand "$LOCAL_RUN_AFTER_CMD" $MAX_EXEC_TIME_PER_CMD_AFTER &
		pids="$!"
	fi

	if [ "$REMOTE_RUN_AFTER_CMD" != "" ]; then
		RunRemoteCommand "$REMOTE_RUN_AFTER_CMD" $MAX_EXEC_TIME_PER_CMD_AFTER &
		pids="$pids;$!"
	fi
	if [ "$pids" != "" ]; then
		WaitForTaskCompletion $pids 0 0 ${FUNCNAME[0]} true $KEEP_LOGGING
	fi
}

function CheckConnectivityRemoteHost {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local retval

	if [ "$_PARANOIA_DEBUG" != "yes" ]; then # Do not loose time in paranoia debug

		if [ "$REMOTE_HOST_PING" != "no" ] && [ "$REMOTE_OPERATION" != "no" ]; then
			eval "$PING_CMD $REMOTE_HOST > /dev/null 2>&1" &
			WaitForTaskCompletion $! 60 180 ${FUNCNAME[0]} true $KEEP_LOGGING
			retval=$?
			if [ $retval != 0 ]; then
				Logger "Cannot ping [$REMOTE_HOST]. Return code [$retval]." "WARN"
				return $retval
			fi
		fi
	fi
}

function CheckConnectivity3rdPartyHosts {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local remote3rdPartySuccess
	local retval

	if [ "$_PARANOIA_DEBUG" != "yes" ]; then # Do not loose time in paranoia debug

		if [ "$REMOTE_3RD_PARTY_HOSTS" != "" ]; then
			remote3rdPartySuccess=false
			for i in $REMOTE_3RD_PARTY_HOSTS
			do
				eval "$PING_CMD $i > /dev/null 2>&1" &
				WaitForTaskCompletion $! 180 360 ${FUNCNAME[0]} true $KEEP_LOGGING
				retval=$?
				if [ $retval != 0 ]; then
					Logger "Cannot ping 3rd party host [$i]. Return code [$retval]." "NOTICE"
				else
					remote3rdPartySuccess=true
				fi
			done

			if [ $remote3rdPartySuccess == false ]; then
				Logger "No remote 3rd party host responded to ping. No internet ?" "WARN"
				return 1
			else
				return 0
			fi
		fi
	fi
}

#__BEGIN_WITH_PARANOIA_DEBUG
function __CheckArguments {
	# Checks the number of arguments of a function and raises an error if some are missing

	if [ "$_DEBUG" == "yes" ]; then
		local numberOfArguments="${1}" # Number of arguments the tested function should have, can be a number of a range, eg 0-2 for zero to two arguments
		local numberOfGivenArguments="${2}" # Number of arguments that have been passed
		local functionName="${3}" # Function name that called __CheckArguments

		local minArgs
		local maxArgs

		if [ "$_PARANOIA_DEBUG" == "yes" ]; then
			Logger "Entering function [$functionName]." "DEBUG"
		fi

		# All arguments of the function to check are passed as array in ${4} (the function call waits for $@)
		# If any of the arguments contains spaces, bash things there are two aguments
		# In order to avoid this, we need to iterate over ${4} and count

		local iterate=4
		local fetchArguments=true
		local argList=""
		local countedArguments
		while [ $fetchArguments == true ]; do
			cmd='argument=${'$iterate'}'
			eval $cmd
			if [ "$argument" = "" ]; then
				fetchArguments=false
			else
				argList="$arg_list [Argument $(($iterate-3)): $argument]"
				iterate=$(($iterate+1))
			fi
		done
		countedArguments=$((iterate-4))

		if [ $(IsNumeric "$numberOfArguments") -eq 1 ]; then
			minArgs=$numberOfArguments
			maxArgs=$numberOfArguments
		else
			IFS='-' read minArgs maxArgs <<< "$numberOfArguments"
		fi

		if ! ([ $countedArguments -ge $minArgs ] && [ $countedArguments -le $maxArgs ]); then
			Logger "Function $functionName may have inconsistent number of arguments. Expected min: $minArgs, max: $maxArgs, count: $countedArguments, bash seen: $numberOfGivenArguments. see log file." "ERROR"
			Logger "Arguments passed: $argList" "ERROR"
		fi
	fi
}

#__END_WITH_PARANOIA_DEBUG

function RsyncPatternsAdd {
	local patternType="${1}"	# exclude or include
	local pattern="${2}"
	__CheckArguments 2 $# ${FUNCNAME[0]} "$@"	#__WITH_PARANOIA_DEBUG

	local rest

	# Disable globbing so wildcards from exclusions do not get expanded
	set -f
	rest="$pattern"
	while [ -n "$rest" ]
	do
		# Take the string until first occurence until $PATH_SEPARATOR_CHAR
		str=${rest%%;*} #TODO: replace ; with $PATH_SEPARATOR_CHAR
		# Handle the last case
		if [ "$rest" = "${rest/$PATH_SEPARATOR_CHAR/}" ]; then
			rest=
		else
			# Cut everything before the first occurence of $PATH_SEPARATOR_CHAR
			rest=${rest#*$PATH_SEPARATOR_CHAR}
		fi
			if [ "$RSYNC_PATTERNS" == "" ]; then
			RSYNC_PATTERNS="--"$patternType"=\"$str\""
		else
			RSYNC_PATTERNS="$RSYNC_PATTERNS --"$patternType"=\"$str\""
		fi
	done
	set +f
}

function RsyncPatternsFromAdd {
	local patternType="${1}"
	local patternFrom="${2}"
	__CheckArguments 2 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

	## Check if the exclude list has a full path, and if not, add the config file path if there is one
	if [ "$(basename $patternFrom)" == "$patternFrom" ]; then
		patternFrom="$(dirname $CONFIG_FILE)/$patternFrom"
	fi

	if [ -e "$patternFrom" ]; then
		RSYNC_PATTERNS="$RSYNC_PATTERNS --"$patternType"-from=\"$patternFrom\""
	fi
}

function RsyncPatterns {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

       if [ "$RSYNC_PATTERN_FIRST" == "exclude" ]; then
		if [ "$RSYNC_EXCLUDE_PATTERN" != "" ]; then
			RsyncPatternsAdd "exclude" "$RSYNC_EXCLUDE_PATTERN"
		fi
		if [ "$RSYNC_EXCLUDE_FROM" != "" ]; then
			RsyncPatternsFromAdd "exclude" "$RSYNC_EXCLUDE_FROM"
		fi
		if [ "$RSYNC_INCLUDE_PATTERN" != "" ]; then
			RsyncPatternsAdd "$RSYNC_INCLUDE_PATTERN" "include"
		fi
		if [ "$RSYNC_INCLUDE_FROM" != "" ]; then
			RsyncPatternsFromAdd "include" "$RSYNC_INCLUDE_FROM"
		fi
	# Use default include first for quicksync runs
	elif [ "$RSYNC_PATTERN_FIRST" == "include" ] || [ "$_QUICK_SYNC" == "2" ]; then
		if [ "$RSYNC_INCLUDE_PATTERN" != "" ]; then
			RsyncPatternsAdd "include" "$RSYNC_INCLUDE_PATTERN"
		fi
		if [ "$RSYNC_INCLUDE_FROM" != "" ]; then
			RsyncPatternsFromAdd "include" "$RSYNC_INCLUDE_FROM"
		fi
		if [ "$RSYNC_EXCLUDE_PATTERN" != "" ]; then
			RsyncPatternsAdd "exclude" "$RSYNC_EXCLUDE_PATTERN"
		fi
		if [ "$RSYNC_EXCLUDE_FROM" != "" ]; then
			RsyncPatternsFromAdd "exclude" "$RSYNC_EXCLUDE_FROM"
		fi
	else
		Logger "Bogus RSYNC_PATTERN_FIRST value in config file. Will not use rsync patterns." "WARN"
	fi
}

function PreInit {
	 __CheckArguments 0 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

	local compressionString

	## SSH compression
	if [ "$SSH_COMPRESSION" != "no" ]; then
		SSH_COMP=-C
	else
		SSH_COMP=
	fi

	## Ignore SSH known host verification
	if [ "$SSH_IGNORE_KNOWN_HOSTS" == "yes" ]; then
		SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
	fi

	## Support for older config files without RSYNC_EXECUTABLE option
	if [ "$RSYNC_EXECUTABLE" == "" ]; then
		RSYNC_EXECUTABLE=rsync
	fi

	## Sudo execution option
	if [ "$SUDO_EXEC" == "yes" ]; then
		if [ "$RSYNC_REMOTE_PATH" != "" ]; then
			RSYNC_PATH="sudo $RSYNC_REMOTE_PATH/$RSYNC_EXECUTABLE"
		else
			RSYNC_PATH="sudo $RSYNC_EXECUTABLE"
		fi
		COMMAND_SUDO="sudo"
	else
		if [ "$RSYNC_REMOTE_PATH" != "" ]; then
			RSYNC_PATH="$RSYNC_REMOTE_PATH/$RSYNC_EXECUTABLE"
		else
			RSYNC_PATH="$RSYNC_EXECUTABLE"
		fi
		COMMAND_SUDO=""
	fi

	 ## Set rsync default arguments
	RSYNC_ARGS="-rltD"
	if [ "$_DRYRUN" == true ]; then
		RSYNC_DRY_ARG="-n"
		DRY_WARNING="/!\ DRY RUN "
	else
		RSYNC_DRY_ARG=""
	fi

	RSYNC_ATTR_ARGS=""
	if [ "$PRESERVE_PERMISSIONS" != "no" ]; then
		RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -p"
	fi
	if [ "$PRESERVE_OWNER" != "no" ]; then
		RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -o"
	fi
	if [ "$PRESERVE_GROUP" != "no" ]; then
		RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -g"
	fi
	if [ "$PRESERVE_ACL" == "yes" ]; then
		RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -A"
	fi
	if [ "$PRESERVE_XATTR" == "yes" ]; then
		RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -X"
	fi
	if [ "$RSYNC_COMPRESS" == "yes" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" -z"
	fi
	if [ "$COPY_SYMLINKS" == "yes" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" -L"
	fi
	if [ "$KEEP_DIRLINKS" == "yes" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" -K"
	fi
	if [ "$PRESERVE_HARDLINKS" == "yes" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" -H"
	fi
	if [ "$CHECKSUM" == "yes" ]; then
		RSYNC_TYPE_ARGS=$RSYNC_TYPE_ARGS" --checksum"
	fi
	if [ "$BANDWIDTH" != "" ] && [ "$BANDWIDTH" != "0" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" --bwlimit=$BANDWIDTH"
	fi

	if [ "$PARTIAL" == "yes" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" --partial --partial-dir=\"$PARTIAL_DIR\""
		RSYNC_PARTIAL_EXCLUDE="--exclude=\"$PARTIAL_DIR\""
	fi

	if [ "$DELTA_COPIES" != "no" ]; then
		RSYNC_ARGS=$RSYNC_ARGS" --no-whole-file"
	else
		RSYNC_ARGS=$RSYNC_ARGS" --whole-file"
	fi

	 ## Set compression executable and extension
	if [ "$(IsInteger $COMPRESSION_LEVEL)" -eq 0 ]; then
		COMPRESSION_LEVEL=3
	fi

	## Busybox fix (Termux xz command doesn't support compression at all)
	if [ "$LOCAL_OS" == "BUSYBOX" ] || [ "$REMOTE_OS" == "BUSYBOX" ]; then
		compressionString=""
		if type gzip > /dev/null 2>&1
		then
			COMPRESSION_PROGRAM="| gzip -c$compressionString"
			COMPRESSION_EXTENSION=.gz
			# obackup specific
		else
			COMPRESSION_PROGRAM=
			COMPRESSION_EXTENSION=
		fi
	else
		compressionString=" -$COMPRESSION_LEVEL"

		if type xz > /dev/null 2>&1
		then
			COMPRESSION_PROGRAM="| xz -c$compressionString"
			COMPRESSION_EXTENSION=.xz
		elif type lzma > /dev/null 2>&1
		then
			COMPRESSION_PROGRAM="| lzma -c$compressionString"
			COMPRESSION_EXTENSION=.lzma
		elif type pigz > /dev/null 2>&1
		then
			COMPRESSION_PROGRAM="| pigz -c$compressionString"
			COMPRESSION_EXTENSION=.gz
			# obackup specific
			COMPRESSION_OPTIONS=--rsyncable
		elif type gzip > /dev/null 2>&1
		then
			COMPRESSION_PROGRAM="| gzip -c$compressionString"
			COMPRESSION_EXTENSION=.gz
			# obackup specific
			COMPRESSION_OPTIONS=--rsyncable
		else
			COMPRESSION_PROGRAM=
			COMPRESSION_EXTENSION=
		fi
	fi
	ALERT_LOG_FILE="$ALERT_LOG_FILE$COMPRESSION_EXTENSION"
}

function PostInit {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

	# Define remote commands
	if [ -f "$SSH_RSA_PRIVATE_KEY" ]; then
		SSH_CMD="$(type -p ssh) $SSH_COMP -i $SSH_RSA_PRIVATE_KEY $SSH_OPTS $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT"
		SCP_CMD="$(type -p scp) $SSH_COMP -i $SSH_RSA_PRIVATE_KEY -P $REMOTE_PORT"
		RSYNC_SSH_CMD="$(type -p ssh) $SSH_COMP -i $SSH_RSA_PRIVATE_KEY $SSH_OPTS -p $REMOTE_PORT"
	elif [ -f "$SSH_PASSWORD_FILE" ]; then
		SSH_CMD="$(type -p sshpass) -f $SSH_PASSWORD_FILE $(type -p ssh) $SSH_COMP $SSH_OPTS $REMOTE_USER@$REMOTE_HOST -p $REMOTE_PORT"
		SCP_CMD="$(type -p sshpass) -f $SSH_PASSWORD_FILE $(type -p scp) $SSH_COMP -P $REMOTE_PORT"
		RSYNC_SSH_CMD="$(type -p sshpass) -f $SSH_PASSWORD_FILE $(type -p ssh) $SSH_COMP $SSH_OPTS -p $REMOTE_PORT"
	else
		SSH_PASSWORD=""
		SSH_CMD=""
		SCP_CMD=""
		RSYNC_SSH_CMD=""
	fi
}

function InitLocalOSSettings {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

	## If running under Msys, some commands do not run the same way
	## Using mingw version of find instead of windows one
	## Getting running processes is quite different
	## Ping command is not the same
	if [ "$LOCAL_OS" == "msys" ]; then
		FIND_CMD=$(dirname $BASH)/find
		PING_CMD='$SYSTEMROOT\system32\ping -n 2'
	else
		FIND_CMD=find
		PING_CMD="ping -c 2 -i .2"
	fi

	if [ "$LOCAL_OS" == "BUSYBOX" ]; then
		PROCESS_STATE_CMD="echo none"
	else
		PROCESS_STATE_CMD='ps -p$pid -o state= 2 > /dev/null'
	fi

	## Stat command has different syntax on Linux and FreeBSD/MacOSX
	if [ "$LOCAL_OS" == "MacOSX" ] || [ "$LOCAL_OS" == "BSD" ]; then
		# Tested on BSD and Mac
		STAT_CMD="stat -f \"%Sm\""
		STAT_CTIME_MTIME_CMD="stat -f %N;%c;%m"
	else
		# Tested on GNU stat and busybox
		STAT_CMD="stat -c %y"
		STAT_CTIME_MTIME_CMD="stat -c %n;%Z;%Y"
	fi
}

function InitRemoteOSSettings {
	__CheckArguments 0 $# ${FUNCNAME[0]} "$@"    #__WITH_PARANOIA_DEBUG

	## MacOSX does not use the -E parameter like Linux or BSD does (-E is mapped to extended attrs instead of preserve executability)
	if [ "$PRESERVE_EXECUTABILITY" != "no" ];then
		if [ "$LOCAL_OS" != "MacOSX" ] && [ "$REMOTE_OS" != "MacOSX" ]; then
			RSYNC_ATTR_ARGS=$RSYNC_ATTR_ARGS" -E"
		fi
	fi

	if [ "$REMOTE_OS" == "msys" ]; then
		REMOTE_FIND_CMD=$(dirname $BASH)/find
	else
		REMOTE_FIND_CMD=find
	fi

	## Stat command has different syntax on Linux and FreeBSD/MacOSX
	if [ "$LOCAL_OS" == "MacOSX" ] || [ "$LOCAL_OS" == "BSD" ]; then
		REMOTE_STAT_CMD="stat -f \"%Sm\""
		REMOTE_STAT_CTIME_MTIME_CMD="stat -f \\\"%N;%c;%m\\\""
	else
		REMOTE_STAT_CMD="stat --format %y"
		REMOTE_STAT_CTIME_MTIME_CMD="stat -c \\\"%n;%Z;%Y\\\""
	fi

}

## IFS debug function
function PrintIFS {
	printf "IFS is: %q" "$IFS"
}

# Process debugging
# Recursive function to get all parents from a pid
function ParentPid {
	local pid="${1}" # Pid to analyse
	local parent

	parent=$(ps -p $pid -o ppid=)
	echo "$pid is a child of $parent"
	if [ $parent -gt 0 ]; then
		ParentPid $parent
	fi
}

## END Generic functions
