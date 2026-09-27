#############################################################################################################################
## create an exit call to reset the cursor.

# ── Non-interactive safety ───────────────────────────────────────────────────
# The waiters below were written for an ATTACHED TERMINAL: they ask the terminal
# where the cursor is with an ANSI DSR escape, then repaint in place with tput.
#
# Under nohup, CI, or any ssh without a TTY there is no terminal to answer. The
# DSR read fails, $startRow is left EMPTY, and the following `tput cup  0` exits
# non-zero -- which under the callers' `set -e` (setup-01-basic.sh:5) kills the
# whole install. Observed 2026-09-22: the run died at the first
# WaitForPodsRunning leaving nothing in the log but
#   failed with error: 1 ;
#   tput: No value for $TERM and no -T specified
# which reads as a stuck wait rather than an abort.
#
# _tty_available gates the cosmetics; _tput makes any tput call a no-op (and
# always succeeds) when there is no terminal. On a real terminal behaviour is
# byte-for-byte unchanged.
_tty_available() { [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; }
_tput() { if _tty_available; then tput "$@" 2>/dev/null || true; fi; return 0; }

function cleanup() {
    _tput cnorm
}

trap cleanup EXIT

#############################################################################################################################
#############################################################################################################################

# advanceConsole rowCount
advanceConsole(){
 _tput civis      ## hide the cursor
   count=$1
	for (( c=1; c<=$count; c++ )) 
	do 
	    sleep .025
		printf "\n"
	done
 _tput cnorm

}

#############################################################################################################################
#############################################################################################################################

# WaitForPodsRunning namespace grepString sleepTime
function WaitForPodsRunning() {

	ABORT_COUNT=${WAIT_ABORT_COUNT:-60}
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for pod startup...\n"; 
	echo "${KUBECTL:-kubectl} get pods --namespace $namespace | grep -i -E $grepStrings"

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 25 lines)
# this may not place the output in the correct locations....

	# startRow is fixed at topRowSpan+1 regardless, so the DSR query only ever
	# fed neededEchos. Skip the whole terminal dance when there is no terminal.
	topRowSpan=5
	startRow=$(( topRowSpan + 1 ))
	if _tty_available; then
		IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
		probedRow=${pos[1]:-0}
		totalLines=$(tput lines 2>/dev/null || echo 24)
		neededEchos=0
		if [[ ${probedRow:-0} -gt $topRowSpan ]]; then
			neededEchos=$(( totalLines - topRowSpan ))
		fi
		advanceConsole $neededEchos
		_tput cup $startRow 0
	fi

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		_tput cup $startRow 0
		_tput ed
		
		check_result=($(${KUBECTL:-kubectl} get pods --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,3))
		
		if [[ ${#check_result[@]} -gt 0 ]]; then
		
			notRunning=0
			for key in "${!check_result[@]}"; do
				if [[ $((key % 2)) -eq 0 ]]; then
					name="${check_result[$key]}"
					running="${check_result[$key + 1]}"
					printf "%s is %s\n" "$name" "$running"
					if [[ "$running" != "Running" ]]; then
						notRunning=1
					fi
				fi
			done
			
			if  [[ $notRunning -eq 1 ]]; then
				sleep $sleepDelay
				((currentCount+=1))
			fi
		else
			echo "Waiting for init ..."
			sleep 5
			((currentCount+=1))
		fi
	done
	echo ""
	if  [[ $notRunning -eq 1 ]]; then
		echo "ERROR *******  CHECK EXITING WITHOUT 'STARTED' CONDITION"
		return 1
	fi

}

#############################################################################################################################
#############################################################################################################################

# WaitForDeploymentToComplete namespace grepString sleepTime
function WaitForDeploymentToComplete() {

	ABORT_COUNT=${WAIT_ABORT_COUNT:-60}
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for deployment to complete...\n"; 
	echo "${KUBECTL:-kubectl} get deployments --namespace $namespace | grep -i -E $grepStrings "

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 15 lines)
# this may not place the output in the correct locations....

	# startRow is fixed at topRowSpan+1 regardless, so the DSR query only ever
	# fed neededEchos. Skip the whole terminal dance when there is no terminal.
	topRowSpan=5
	startRow=$(( topRowSpan + 1 ))
	if _tty_available; then
		IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
		probedRow=${pos[1]:-0}
		totalLines=$(tput lines 2>/dev/null || echo 24)
		neededEchos=0
		if [[ ${probedRow:-0} -gt $topRowSpan ]]; then
			neededEchos=$(( totalLines - topRowSpan ))
		fi
		advanceConsole $neededEchos
		_tput cup $startRow 0
	fi

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		_tput cup $startRow 0
		_tput ed
		
		check_result=($(${KUBECTL:-kubectl} get deployments --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,3))
		
		if [[ ${#check_result[@]} -gt 0 ]]; then
		
			notRunning=0
			for key in "${!check_result[@]}"; do
				if [[ $((key % 2)) -eq 0 ]]; then
					name="${check_result[$key]}"
					running="${check_result[$key + 1]}"

					printf "%s available is %s\n" "$name" "$running"
					if [[ "$running" -eq "0" ]]; then
						notRunning=1
					fi
				fi
			done
			
			if  [[ $notRunning -eq 1 ]]; then
				sleep $sleepDelay
				((currentCount+=1))
			fi
		else
			echo "Waiting for init ..."
			sleep 5
			((currentCount+=1))
		fi
	done
	if  [[ $notRunning -eq 1 ]]; then
		echo "ERROR *******  CHECK EXITING WITHOUT 'STARTED' CONDITION"
		return 1
	fi
}

#############################################################################################################################
#############################################################################################################################
	
# WaitForDeploymentToComplete namespace grepString sleepTime
function WaitForServiceToStart() {

	ABORT_COUNT=${WAIT_ABORT_COUNT:-60}
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for services to start...\n"; 
	echo "${KUBECTL:-kubectl} get services --namespace $namespace | grep -i -E $grepStrings"

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 15 lines)
# this may not place the output in the correct locations....

	# startRow is fixed at topRowSpan+1 regardless, so the DSR query only ever
	# fed neededEchos. Skip the whole terminal dance when there is no terminal.
	topRowSpan=5
	startRow=$(( topRowSpan + 1 ))
	if _tty_available; then
		IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
		probedRow=${pos[1]:-0}
		totalLines=$(tput lines 2>/dev/null || echo 24)
		neededEchos=0
		if [[ ${probedRow:-0} -gt $topRowSpan ]]; then
			neededEchos=$(( totalLines - topRowSpan ))
		fi
		advanceConsole $neededEchos
		_tput cup $startRow 0
	fi

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		_tput cup $startRow 0
		_tput ed
		check_result=($(${KUBECTL:-kubectl} get services --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,6))
		
		
		if [[ ${#check_result[@]} -gt 0 ]]; then
		
			rowCount=2
			notRunning=0
			for key in "${!check_result[@]}"; do
				if [[ $((key % 2)) -eq 0 ]]; then
					name="${check_result[$key]}"
					running="${check_result[$key + 1]}"
					
					printf "%s - Age is %s\n" "$name" "$running"
				    ((rowCount+=1))
				fi
			done
			if  [[ $notRunning -eq 1 ]]; then
				sleep $sleepDelay
				((currentCount+=1))
			fi
		else
			echo "Waiting for init ..."
			sleep 5
			((currentCount+=1))
		fi
	done
	if  [[ $notRunning -eq 1 ]]; then
		echo "ERROR *******  CHECK EXITING WITHOUT 'STARTED' CONDITION"
		return 1
	fi
}


#############################################################################################################################

#############################################################################################################################
# repeat {count} {char}
repeat(){
    count=$1
	char="$2"
	echo ""
	for (( c=1; c<=$count; c++ )) 
	do 
		echo -n "$char"; 
	done
	echo ""
}

#############################################################################################################################
# repeatToColWidth {char}
repeatToColWidth(){
    count=$(_tty_available && tput lines 2>/dev/null || echo 80)
	char="$2"
	repeat $count $char
}


# WaitForCRD <crd-name> [<crd-name> ...]
#
# Block until each named CRD reports condition=established.
#
# WHY: 'kubectl apply' returns as soon as the API server accepts the CRD object,
# but the type is not servable until the apiextensions controller establishes it
# and the discovery cache refreshes. Applying a custom resource in the same
# breath as its CRD therefore races, and loses often enough to matter on a cold
# cluster. The failure is the familiar:
#
#   resource mapping not found for name: "..." ... ensure CRDs are installed first
#
# Under 'set -e' that aborts the whole install, and because the enclosing step
# never reaches mark_step_done it can leave a half-built namespace behind.
#
# Always call this between applying a CRD bundle and applying any CR of that
# type. Default timeout 180s per CRD; override with CRD_WAIT_TIMEOUT.
function WaitForCRD() {
    local timeout="${CRD_WAIT_TIMEOUT:-180}"
    local kubectl_bin="${KUBECTL:-kubectl}"
    local crd rc=0
    for crd in "$@"; do
        echo "  waiting for CRD to be established: $crd"
        if ! $kubectl_bin wait --for condition=established --timeout="${timeout}s" "crd/$crd"; then
            echo "  ERROR: CRD '$crd' was not established within ${timeout}s" >&2
            rc=1
        fi
    done
    return $rc
}
