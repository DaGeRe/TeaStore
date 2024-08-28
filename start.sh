#!/bin/bash

java -jar utilities/receiver.jar 10001 > "kieker-receiver.log" &
disown
