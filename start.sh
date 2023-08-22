if [ $# -lt 1 ]
then
	echo "Please provide IP as parameter!"
	exit 1
fi

echo "Building current version..."

mvn clean package -DskipTests &> build.txt

maven_exit_status=$?
if [ $maven_exit_status -eq 1 ]; then
    echo "Maven build did not succeed - cancelling"
    exit 1
fi

#cd tools && ./build_docker.sh >> ../build.txt && cd ..

MY_IP=$1
MY_FOLDER=$(pwd)/kieker-results/

set -e
if [ -d $MY_FOLDER ]
then
	sudo rm -rf $MY_FOLDER
fi

mkdir -p $MY_FOLDER

echo "Creating docker containers..."

docker run -p 3306:3306 -d --network=bridge teastore-db
docker run -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=10000" -p 10000:8080 -d --network=bridge teastore-registry
docker run -v $MY_FOLDER/teastore-persistence:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=1111" -e "DB_HOST=$MY_IP" -e "DB_PORT=3306" -p 1111:8080 -d --network=bridge teastore-persistence
docker run -v $MY_FOLDER/teastore-auth:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=2222" -p 2222:8080 -d --network=bridge teastore-auth
docker run --name recommender -v $MY_FOLDER/teastore-recommender:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=3333" -p 3333:8080 -d --network=bridge teastore-recommender
docker run -v $MY_FOLDER/teastore-image:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=4444" -p 4444:8080 -d --network=bridge teastore-image
docker run -v $MY_FOLDER/teastore-webui:/kieker/logs/ -e "LOG_TO_FILE=true" -e "REGISTRY_HOST=$MY_IP" -e "REGISTRY_PORT=10000" -e "HOST_NAME=$MY_IP" -e "SERVICE_PORT=8080" -p 8080:8080 -d --network=bridge teastore-webui

attempt=0
while [ $attempt -le 59 ]; do
    attempt=$(( $attempt + 1 ))
    echo "Waiting for Tomcat to be up (attempt: $attempt)..."
    result=$(docker logs recommender 2>&1)
    if grep -q 'org.apache.catalina.startup.Catalina.start Server startup in ' <<< $result ; then
      echo "Tomcat is up!"
      break
    fi
    sleep 2
done

