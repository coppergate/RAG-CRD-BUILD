#############################################################################################################################
## create an exit call to reset the cursor.

function cleanup() {
    tput cnorm
}

trap cleanup EXIT

#############################################################################################################################
#############################################################################################################################

# advanceConsole rowCount
advanceConsole(){
 tput civis      ## hide the cursor
   count=$1
	for (( c=1; c<=$count; c++ )) 
	do 
	    sleep .025
		printf "\n"
	done
 tput cnorm

}

#############################################################################################################################
#############################################################################################################################

# WaitForPodsRunning namespace grepString sleepTime
function WaitForPodsRunning() {

	ABORT_COUNT=20
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for pod startup...\n"; 
	echo "kubectl get pods --namespace $namespace | grep -i -E $grepStrings"

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 25 lines)
# this may not place the output in the correct locations....

	IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
	startRow=${pos[1]}
	totalLines=`tput lines`
	
	topRowSpan=5
	neededEchos=0
	if [[ $startRow -gt $topRowSpan ]]; then
		neededEchos=$(( totalLines -  topRowSpan ))
	fi
	let startRow=topRowSpan+1
	advanceConsole $neededEchos
	tput cup $startRow 0

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		tput cup $startRow 0
		tput ed;
		
		check_result=($(kubectl get pods --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,3))
		
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
	fi

}

#############################################################################################################################
#############################################################################################################################

# WaitForDeploymentToComplete namespace grepString sleepTime
function WaitForDeploymentToComplete() {

	ABORT_COUNT=20
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for deployment to complete...\n"; 
	echo "kubectl get deployments --namespace $namespace | grep -i -E $grepStrings "

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 15 lines)
# this may not place the output in the correct locations....

	IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
	startRow=${pos[1]}
	totalLines=`tput lines`
	
	topRowSpan=5
	neededEchos=0
	if [[ $startRow -gt $topRowSpan ]]; then
		neededEchos=$(( totalLines -  topRowSpan ))
	fi
	let startRow=topRowSpan+1
	advanceConsole $neededEchos
	tput cup $startRow 0

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		tput cup $startRow 0
		tput ed;
		
		check_result=($(kubectl get deployments --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,3))
		
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
	fi
}

#############################################################################################################################
#############################################################################################################################
	
# WaitForDeploymentToComplete namespace grepString sleepTime
function WaitForServiceToStart() {

	ABORT_COUNT=20
	currentCount=0
	
	notRunning=1
	
	namespace=$1
	grepStrings=$2
	sleepDelay=$3
    printf "waiting for services to start...\n"; 
	echo "kubectl get services --namespace $namespace | grep -i -E $grepStrings"

# We're going to try to put the output location so that all of the check returns
# display without issue...  if the terminal is very short (say less than 15 lines)
# this may not place the output in the correct locations....

	IFS='[;' read -p $'\e[6n' -d R -a pos -rs || echo "failed with error: $? ; ${pos[*]}"
	startRow=${pos[1]}
	totalLines=`tput lines`
	
	topRowSpan=5
	neededEchos=0
	if [[ $startRow -gt $topRowSpan ]]; then
		neededEchos=$(( totalLines -  topRowSpan ))
	fi
	let startRow=topRowSpan+1
	advanceConsole $neededEchos
	tput cup $startRow 0

	
	while [[ $notRunning -eq 1 && $currentCount -lt $ABORT_COUNT ]] ; do
	
		tput cup $startRow 0
		tput ed;
		check_result=($(kubectl get services --namespace $namespace | grep -i -E $grepStrings | sed -e "s/ \+  /\t/g" | cut --fields=1,6))
		
		
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
    count=`tput lines`
	char="$2"
	repeat $count $char
}

