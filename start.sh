#!/bin/bash

function waitForContainerStartup {
	containerName=$1
	textToWaitFor=$2
	
	echo "Waiting for $containerName to be ready"
	attempt=0
	while [ $attempt -le 300 ]; do
	    attempt=$(( $attempt + 1 ))
	    echo "Waiting for $containerName to be up (attempt: $attempt)..."
	    result=$(docker logs $containerName 2>&1)
	    if grep -q "$textToWaitFor" <<< $result ; then
	      echo "$containerName is up!"
	      break
	    fi
	    sleep 2
	done
}

if [ $# -lt 1 ]
then
	echo "Please provide IP as parameter!"
	exit 1
fi

if [[ "$2" == "TCP" ]]
then
	nohup java -jar utilities/receiver.jar 10001 > "kieker-receiver.log" &
	
	sed -i "s/kieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter/#kieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
	sed -i "s/#kieker.monitoring.writer=kieker.monitoring.writer.tcp.SingleSocketTcpWriter/kieker.monitoring.writer=kieker.monitoring.writer.tcp.SingleSocketTcpWriter/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
	sed -i "s/kieker.monitoring.writer.tcp.SingleSocketTcpWriter.hostname=localhost/kieker.monitoring.writer.tcp.SingleSocketTcpWriter.hostname=$MY_IP/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
	
fi
