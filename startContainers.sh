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
	    sleep 5
	done
}

function waitForFullstartup() {
	attempt=0
	while [ $attempt -le 300 ]; do
		# Check the status using curl and grep
		if ! curl -s http://localhost:8080/tools.descartes.teastore.webui/status 2>&1 | grep -q "Offline"
		then
			echo "Service is online. Exiting..."
		break
		fi
		echo "Services are still partially offline. Checking again in 5 seconds..."
		sleep 5
	done
}

if [ $# -lt 1 ]
then
	echo "Please provide IP as parameter!"
	exit 1
fi

MY_IP=$1
BASE_DIR=`pwd`
MY_FOLDER="$BASE_DIR/kieker-results/"

set -e

source functions.sh

#resetInstrumentationFiles

if [ "$2" ]
then
	ec
	case "$2" in
		"NO_INSTRUMENTATION") removeAllInstrumentation ;;
		"DEACTIVATED") 
			git checkout -- utilities/tools.descartes.teastore.dockerbase/start.sh
			sed -i 's/\(export JAVA_OPTS=".*\)"/\1 -Dkieker.monitoring.enabled=false"/' utilities/tools.descartes.teastore.dockerbase/start.sh
			;;
		"NOLOGGING")
			git checkout -- utilities/tools.descartes.teastore.dockerbase/start.sh
			sed -i 's/\(export JAVA_OPTS=".*\)"/\1 -Dkieker.monitoring.writer=kieker.monitoring.writer.dump.DumpWriter -Dkieker.monitoring.core.controller.WriterController.RecordQueueFQN=kieker.monitoring.writer.dump.DumpQueue"/' utilities/tools.descartes.teastore.dockerbase/start.sh
			;;
		"TCP")
			java -jar utilities/receiver.jar 10001 > "kieker-receiver.log" &
	
			sed -i "s/kieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter/#kieker.monitoring.writer=kieker.monitoring.writer.filesystem.FileWriter/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
			sed -i "s/#kieker.monitoring.writer=kieker.monitoring.writer.tcp.SingleSocketTcpWriter/kieker.monitoring.writer=kieker.monitoring.writer.tcp.SingleSocketTcpWriter/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
			sed -i "s/kieker.monitoring.writer.tcp.SingleSocketTcpWriter.hostname=localhost/kieker.monitoring.writer.tcp.SingleSocketTcpWriter.hostname=$1/g" utilities/tools.descartes.teastore.dockerbase/kieker.monitoring.properties
			;;
		"KIEKER_ASPECTJ_BINARY")
			echo "Not supported yet";
			exit 1;
			;;
		"KIEKER_BYTEBUDDY_TEXT")
			instrumentForKiekerBytebuddy
		"KIEKER_BYTEBUDDY_BINARY")
			echo "Not supported yet";
			exit 1;
			;;
		"OPENTELEMETRY_DEACTIVATED")
			removeAllInstrumentation
			instrumentForOpenTelemetry $MY_IP "DEACTIVATED"
			;;
		"OPENTELEMETRY_SPANS")
			removeAllInstrumentation
			instrumentForOpenTelemetry $MY_IP
			;;
		*) echo "Configuration $2 not found; Exiting"; exit 1;;
esac
fi

echo "Building current version..."

mvn clean package -DskipTests &> build.txt

maven_exit_status=$?
if [ $maven_exit_status -eq 1 ]; then
    echo "Maven build did not succeed - cancelling"
    exit 1
fi

cd tools && ./build_docker.sh >> ../build.txt && cd ..

if [ -d $MY_FOLDER ] && [ ! -z "$( ls -A $MY_FOLDER )" ]
then
	docker run --rm -v $MY_FOLDER:/kieker-results alpine sh -c "rm -rf /kieker-results/*"
#	sudo rm -rf $MY_FOLDER/*
fi

mkdir -p $MY_FOLDER

echo "Creating docker containers..."

docker run --hostname=teastore-db-1 \
	-p 3306:3306 -d teastore-db
docker run --hostname=teastore-registry-1 \
	-e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=10000" -p 10000:8080 -d teastore-registry 
docker run --hostname=teastore-persistence-1 \
	-v $MY_FOLDER/teastore-persistence:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=1111" -e "DB_HOST=$MY_IP" -e "DB_PORT=3306" -p 1111:8080 -d teastore-persistence
docker run --hostname=teastore-auth-1 \
	-v $MY_FOLDER/teastore-auth:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=2222" -p 2222:8080 -d teastore-auth
docker run --hostname=teastore-recommender-1 \
	--name recommender -v $MY_FOLDER/teastore-recommender:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=3333" -p 3333:8080 -d teastore-recommender
docker run --hostname=teastore-image-1 \
	-v $MY_FOLDER/teastore-image:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=4444" -p 4444:8080 -d teastore-image
docker run --hostname=teastore-webui-1 \
	-v $MY_FOLDER/teastore-webui:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=8080" -p 8080:8080 -d teastore-webui

waitForContainerStartup recommender 'org.apache.catalina.startup.Catalina.start Server startup in '

database_id=$(docker ps | grep "teastore-db" | awk '{print $1}')
waitForContainerStartup $database_id 'port: 3306'

waitForFullstartup