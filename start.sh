#!/bin/bash

setsid --fork java -jar utilities/receiver.jar 10001 > "kieker-receiver.log"
echo "Exiting..."
exit
