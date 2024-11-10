#!/bin/bash

if [ $# -lt 1 ]
then
	echo "Please provide IP as parameter!"
	exit 1
fi

if [ $# -gt 3 ]
then
	container_id=$3
	agent_ip=$4
	if [[ $agent_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
	then
		echo "IP $agent_ip will be used for the current host"
	else
		echo "IP $agent_ip not valid; exiting"
		exit 1
	fi
else
	container_id="1"
fi

MY_IP=$1
BASE_DIR=`pwd`
MY_FOLDER="$BASE_DIR/kieker-results/"

set -e

source executionControl/functions.sh

if [ "$2" ]
then
	resetInstrumentationFiles
	
	RECURSION_DEPTH=$3
	sed -i "/ENV USE_HTTPS false/a ENV RECURSION_DEPTH $RECURSION_DEPTH" utilities/tools.descartes.teastore.dockerbase/Dockerfile
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
		"KIEKER_ASPECTJ_TEXT")
			# Do nothing, since this is the default configuration
			;;
		"KIEKER_ASPECTJ_BINARY")
			useBinaryWriterKieker
			;;
		"KIEKER_ASPECTJ_TCP")
			# nohup is necessary on Rocky Linux, otherwise, the process gets finished after script end; with Ubuntu, it works without
			docker run -d -p 10001:10001 --name kieker-receiver-1 -v $(pwd)/utilities/receiver.jar:/app/receiver.jar eclipse-temurin:latest java -jar /app/receiver.jar 10001 
	
			useTCPWriterKieker $MY_IP
			;;
		"KIEKER_BYTEBUDDY_TEXT")
			instrumentForKiekerBytebuddy
			;;
		"KIEKER_BYTEBUDDY_BINARY")
			instrumentForKiekerBytebuddy
			useBinaryWriterKieker
			;;
		"KIEKER_BYTEBUDDY_TCP")
			# nohup is necessary on Rocky Linux, otherwise, the process gets finished after script end; with Ubuntu, it works without
			docker run -d -p 10001:10001 --name kieker-receiver-1 -v $(pwd)/utilities/receiver.jar:/app/receiver.jar eclipse-temurin:latest java -jar /app/receiver.jar 10001 
	
			instrumentForKiekerBytebuddy
			useTCPWriterKieker $MY_IP
			;;
		"OPENTELEMETRY_DEACTIVATED")
			removeAllInstrumentation
			instrumentForOpenTelemetry $MY_IP "$2"
			;;
		"OPENTELEMETRY_ZIPKIN_MEMORY")
			removeAllInstrumentation
			instrumentForOpenTelemetry $MY_IP "$2"
			;;
		"OPENTELEMETRY_ZIPKIN_ELASTIC")
			removeAllInstrumentation
			instrumentForOpenTelemetry $MY_IP "$2"
			;;
		*) echo "Configuration $2 not found; Exiting"; exit 1;;
esac
fi
if [ $container_id == "1" ]
then
	case "$2" in
		"OPENTELEMETRY_ZIPKIN_MEMORY")
			startZipkinMemory
			;;
		"OPENTELEMETRY_ZIPKIN_ELASTIC")
			startZipkinElastic
			;;
	esac
fi

echo "Building current version..."

./mvnw clean package -DskipTests &> build.txt

maven_exit_status=$?
if [ $maven_exit_status -eq 1 ]; then
    echo "Maven build did not succeed - cancelling"
    exit 1
fi

echo "Building docker containers..."
cd tools && ./build_docker.sh &> ../build_docker.txt && cd ..

if [ -d $MY_FOLDER ] && [ ! -z "$( ls -A $MY_FOLDER )" ]
then
	docker run --rm -v $MY_FOLDER:/kieker-results alpine sh -c "rm -rf /kieker-results/*"
#	sudo rm -rf $MY_FOLDER/*
fi

mkdir -p $MY_FOLDER

echo "Creating docker containers..."

if [ $container_id == "1" ]
then
	docker run --hostname=teastore-db-$container_id \
		-p 3306:3306 -d teastore-db
	docker run --hostname=teastore-registry-$container_id \
		-e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=10000" -p 10000:8080 -d teastore-registry 
	docker run --hostname=teastore-persistence-$container_id \
	-v $MY_FOLDER/teastore-persistence:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=1111" -e "DB_HOST=$MY_IP" -e "DB_PORT=3306" -p 1111:8080 -d teastore-persistence
docker run --hostname=teastore-auth-$container_id \
	-v $MY_FOLDER/teastore-auth:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=2222" -p 2222:8080 -d teastore-auth
docker run --hostname=teastore-recommender-$container_id \
	-v $MY_FOLDER/teastore-recommender:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=3333" -p 3333:8080 -d teastore-recommender
docker run --hostname=teastore-image-$container_id \
	-v $MY_FOLDER/teastore-image:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=4444" -p 4444:8080 -d teastore-image
docker run --hostname=teastore-webui-$container_id \
	-v $MY_FOLDER/teastore-webui:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=8080" -p 8080:8080 -d teastore-webui
	
else
	AGENT_IP=$3
	docker run --hostname=teastore-persistence-$container_id \
		-v $MY_FOLDER/teastore-persistence:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$agent_ip" -e "SERVICE_PORT=1111" -e "DB_HOST=$MY_IP" -e "DB_PORT=3306" -p 1111:8080 -d teastore-persistence
	docker run --hostname=teastore-auth-$container_id \
		-v $MY_FOLDER/teastore-auth:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$agent_ip" -e "SERVICE_PORT=2222" -p 2222:8080 -d teastore-auth
	docker run --hostname=teastore-recommender-$container_id \
		-v $MY_FOLDER/teastore-recommender:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$agent_ip" -e "SERVICE_PORT=3333" -p 3333:8080 -d teastore-recommender
	docker run --hostname=teastore-image-$container_id \
		-v $MY_FOLDER/teastore-image:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$agent_ip" -e "SERVICE_PORT=4444" -p 4444:8080 -d teastore-image
	
	# WebUI seems to be current not distributed
	#docker run --hostname=teastore-webui-$container_id \
	#	-v $MY_FOLDER/teastore-webui:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$agent_ip" -e "SERVICE_PORT=8080" -p 8080:8080 -d teastore-webui
fi

recommender_id=$(docker ps | grep "recommender" | awk '{print $1}')
waitForContainerStartup $recommender_id 'org.apache.catalina.startup.Catalina.start Server startup in '

# the database will only be on the main server
database_id=$(docker ps | grep "teastore-db" | awk '{print $1}')
if [ ! -z "$database_id" ]
then	
	waitForContainerStartup $database_id 'port: 3306'
fi
