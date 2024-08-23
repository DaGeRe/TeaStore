#!/bin/bash

function runOneExperiment {
	PARAMETER=$1
	RESULTFILE=$2
	NUMUSER=$3
	
	ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "teastore\|recommender" | awk "{print $1}" | xargs docker rm -f $1'

	ssh $TEASTORE_RUNNER_IP "cd TeaStore; ls; ./start.sh $HOST_SELF_IP"

	echo
	echo
	echo "Building is finished; Starting load test"

	if [ -f $RESULTFILE ]
	then
	       rm $RESULTFILE
	fi

	echo "Replacing user count by $NUMUSER"
	
	sed -i '/>num_user/{n;s/.*/\            <stringProp name="Argument.value"\>'$NUMUSER'\<\/stringProp\>/}' examples/jmeter/teastore_browse_nogui.jmx

	java -jar $JMETER_HOME/bin/ApacheJMeter.jar \
	       -t examples/jmeter/teastore_browse_nogui.jmx -Jhostname localhost -Jport 8080 -n \
	       -l $RESULTFILE

	echo
	echo
	echo "Load test is finished; Removing containers"

	ssh $TEASTORE_RUNNER_IP 'docker ps -a | grep "teastore\|recommender" | awk "{print $1}" | xargs docker rm -f $1'
	
	sleep 5s
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
if [ $# -gt 1 ]
then
	HOST_SELF_IP=$2
else
	HOST_SELF_IP=$TEASTORE_RUNNER_IP
fi

# Just test connection
ssh -q $1 "exit"

ssh $TEASTORE_RUNNER_IP "if [ ! -d TeaStore ]; then git clone https://github.com/DaGeRe/TeaStore.git; fi"
ssh $TEASTORE_RUNNER_IP "cd TeaStore; git checkout kieker-debug; git pull"

for users in 1 2 4 8 16
do
	runOneExperiment " " aspectj_instrumentation_$users.csv
	runOneExperiment "NO_INSTRUMENTATION" no_instrumentation_$users.csv
done