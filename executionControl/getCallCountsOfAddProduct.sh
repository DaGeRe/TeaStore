function getSum {
  awk -vOFMT=%.10g '{sum += $1; square += $1^2} END {print sqrt(square / NR - (sum/NR)^2)" "sum/NR" "NR}'
}

function analyzeCallCounts {
	FOLDER=$1
	SERVLET=$2
	# for call counts, we need grep $SERVLET -A 1
	traceIds=$(cat $FOLDER/teastore-*/*/*.dat | grep -v "RegistryClient\$1.<init>" | grep $SERVLET | awk -F';' '{print $5}')

	echo -n "#Service Call Counts: "
	echo $traceIds | awk '{print NF}'

	for traceId in $traceIds
	do
		echo -n "$traceId "
		cat $1/teastore-*/*/*.dat | grep $traceId | wc -l
	done

#	for traceId in $traceIds
#	do
#		echo -n "$traceId "
#		grep $traceId $1/teastore-*/*/*.dat | awk -F';' '{print $8}' | uniq | wc -l
#	done
}

#analyzeCallCounts $1 LoginActionServlet

for servlet in LoginActionServlet CartServlet IndexServlet CartActionServlet CategoryServlet ProductServlet
do
	echo "Analyzing: $servlet"
	analyzeCallCounts $1 $servlet
done
