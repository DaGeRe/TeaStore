#!/bin/bash

function getSum {
  awk '{sum += $1; square += $1^2} END {print sqrt(square / NR - (sum/NR)^2)" "sum/NR" "NR}'
}

function runLoadTest {
	RESULTFILE=$1
	NUMUSER=$2
	RESULTFILE_CPU=$3
	echo
	echo
	echo "Building is finished; Starting load test"

	if [ -f $RESULTFILE ]
	then
	       rm $RESULTFILE
	fi
	
	sleep 60s

	echo "Replacing user count by $NUMUSER"
	sed -i '/>num_user/{n;s/.*/\            <stringProp name="Argument.value"\>'$NUMUSER'\<\/stringProp\>/}' examples/jmeter/teastore_browse_nogui.jmx
	
	echo "Replacing host name by $TEASTORE_RUNNER_IP"
	sed -i '/>hostname/{n;s/.*/\            <stringProp name="Argument.value"\>'$TEASTORE_RUNNER_IP'\<\/stringProp\>/}' examples/jmeter/teastore_browse_nogui.jmx

	JMETER_LOOPS=$(echo "10000/sqrt($NUMUSER)" | bc)
	echo "Replacing loops by $JMETER_LOOPS"
	sed -i '/LoopController.loops/s/.*/\            <stringProp name="LoopController.loops">'$JMETER_LOOPS'<\/stringProp>/' examples/jmeter/teastore_browse_nogui.jmx

	ssh $TEASTORE_RUNNER_IP 'nohup vmstat 1 &> TeaStore/'$RESULTFILE_CPU' & disown'

	java -jar $JMETER_HOME/bin/ApacheJMeter.jar \
	       -t examples/jmeter/teastore_browse_nogui.jmx -n \
	       -l $RESULTFILE

	(ssh -t $TEASTORE_RUNNER_IP 'kill -9 $(pgrep -f vmstat)') || true
	rsync -avz $TEASTORE_RUNNER_IP:"TeaStore/vmstat_*" .
	ssh $TEASTORE_RUNNER_IP 'rm TeaStore/vmstat_*'

	echo
	echo
	echo "Load test is finished; Removing containers"
}

function runOneExperiment {
	PARAMETER=$1
	RESULTFILE=$2
	NUMUSER=$3
	RECURSION_DEPTH=$4
	
	ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "teastore\|recommender\|kieker-receiver" | awk "{print \$1}" | xargs docker rm -f \$1'
	ssh $TEASTORE_RUNNER_IP 'docker images -a | grep none | awk "{print \$3}" | xargs --no-run-if-empty docker rmi $1'
	ssh $TEASTORE_RUNNER_IP 'echo y | docker system prune --volumes'
	
	# Remove Zipkin, otel and elastic after the system has been pruned - we don't need to fetch the images everytime freshly
	ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "zipkin\|otel\|elastic" | awk "{print \$1}" | xargs docker rm -f \$1'
	
	ssh -t $TEASTORE_RUNNER_IP "cd TeaStore; ./startContainers.sh $TEASTORE_RUNNER_IP $PARAMETER $RECURSION_DEPTH"
	sleep 1
	ssh -t $TEASTORE_RUNNER_IP "cd TeaStore/executionControl; ./waitForStartup.sh $TEASTORE_RUNNER_IP" ||
	{
		return_code=$?
		if [ $return_code -ne 0 ]; then
	    		echo "Error: waitForStartup.sh failed with return code $return_code"
	    		return
		fi
	}
	echo 
	echo "Startup completed"
	
	index=2
	for AGENT_IP in "${@:5}"
	do
		ssh $AGENT_IP 'docker ps -a | grep "teastore\|recommender\|kieker-receiver" | awk "{print \$1}" | xargs docker rm -f \$1'
		ssh $AGENT_IP 'docker images -a | grep none | awk "{print \$3}" | xargs --no-run-if-empty docker rmi $1'
		ssh $AGENT_IP 'echo y | docker system prune --volumes'
		
		# Remove Zipkin, otel and elastic after the system has been pruned - we don't need to fetch the images everytime freshly
		ssh $AGENT_IP 'docker ps -a | grep "zipkin\|otel\|elastic" | awk "{print \$1}" | xargs docker rm -f \$1'
		
		ssh -t $AGENT_IP "cd TeaStore; ./startContainers.sh $TEASTORE_RUNNER_IP $PARAMETER $index $AGENT_IP"
		ssh -t $TEASTORE_RUNNER_IP "cd TeaStore/executionControl; ./waitForStartup.sh $TEASTORE_RUNNER_IP"
		((index++))
	done

	runLoadTest $RESULTFILE $NUMUSER "vmstat_"$RESULTFILE

	ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "teastore\|recommender" | awk "{print \$1}" | xargs docker rm -f \$1'
	
	if [[ "$PARAMETER" == "KIEKER_ASPECTJ_TCP" || "$PARAMETER" == "KIEKER_BYTEBUDDY_TCP" ]]
	then
		echo "Stopping receiver"
		ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "teastore\|recommender\|kieker-receiver" | awk "{print \$1}" | xargs docker rm -f \$1'
		
		# Old variant, with Kieker-receiver as process on the host - usually creates problems with ports and docker, so don't use for now
		# Don't fail on the next one, it usually works and still gives return code 255
		#(ssh -t $TEASTORE_RUNNER_IP 'kill -9 $(pgrep -f receiver.jar)') || true
	fi
	
	sleep 5s
}

function setupServer {
	CONNECTION_IP=$1
	
	ssh -q $CONNECTION_IP "exit"

	ssh $CONNECTION_IP "if [ ! -d TeaStore ]; then git clone https://github.com/DaGeRe/TeaStore.git; fi"
	ssh $CONNECTION_IP "cd TeaStore; git checkout kieker-debug; git pull"
}

set -e

if [ $# -lt 1 ]
then
	echo "Please provide IP as parameter!"
	exit 1
fi

if [ "$JMETER_HOME" == "" ] || [ ! -d $JMETER_HOME ] 
then
	echo "\$JMETER_HOME needs to be a directory!"
	exit 1
fi

TEASTORE_RUNNER_IP=$1

# Just test connection
setupServer $TEASTORE_RUNNER_IP

for AGENT_IP in "${@:2}"
do
	echo
	echo "Setting up $AGENT_IP"
	setupServer $AGENT_IP
done

for RECURSION_DEPTH in 0 10 20 40 100 200 300 400 500
do
	durations=""
	loops=10
	for (( iteration=1; iteration<=$loops; iteration++ ))
	do
		start=$(date +%s%N)
		for NUMUSER in 1 2 4 8
		do
			runOneExperiment "NO_INSTRUMENTATION" no_instrumentation_$NUMUSER"_"$iteration.csv $NUMUSER $RECURSION_DEPTH ${@:2}
			runOneExperiment "KIEKER_ASPECTJ_BINARY" kieker_aspectj_binary_$NUMUSER"_"$iteration.csv $NUMUSER $RECURSION_DEPTH ${@:2}
			runOneExperiment "KIEKER_BYTEBUDDY_BINARY" kieker_bytebuddy_binary_$NUMUSER"_"$iteration.csv $NUMUSER $RECURSION_DEPTH ${@:2}
			runOneExperiment "OPENTELEMETRY_ZIPKIN_MEMORY" otel_memory_$NUMUSER"_"$iteration.csv $NUMUSER $RECURSION_DEPTH ${@:2}
			runOneExperiment "OPENTELEMETRY_ZIPKIN_ELASTIC" otel_elastic_$NUMUSER"_"$iteration.csv $NUMUSER $RECURSION_DEPTH ${@:2}
		done
		end=$(date +%s%N)
		duration=$(echo "($end-$start)/1000000" | bc)
		durations="$durations $duration"
		average=$(echo $durations | getSum | awk '{print $2/1000}')
		remaining=$(echo "scale=2; $average*($loops-$iteration)/60" | bc -l)
		echo " Remaining: $remaining minutes"
	done
done
