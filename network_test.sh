#!/bin/bash

# Default settings
cnf_verbose=0 # Display test information on stdout also
cnf_only_one_hop=1 # Test only to directly neighboring nodes
cnf_repeat_count=20 # How many times to repeat the tests
cnf_run_ping=1 # Whether to conduct ping test
cnf_run_speedtest=1 # Whether to conduct speed test

cnf_map_file="/home/pi/network_monitoring/network_map.csv" # CSV file containing the network map
cnf_my_ip="192.168.1.51" # This node's ip
cnf_log_folder="/var/www/html/network-monitoring/${cnf_my_ip}-log" # Folder where to save logs. Make sure the directory exists!
cnf_ping_internet_ip="8.8.8.8" # ip to ping when doing ping test to internet

# Source config file if specified on command line
if [ "${1}" != "" ]; then # @@@
    . "${1}"
fi

# Log to stdout function
# Function to write text to stdout, prepending
# the script's name, and only if ${cnf_verbose}
# is greater than zero
# Arguments taken: ${@}: (text to be printed)
network_test_log_stdout() {
    if [ "${cnf_verbose}" -gt 0 ]; then
	echo -e "${0}: ${@}"
    fi
}

network_test_log_stdout "Starting..."

# Read the network map file, excluding comment lines starting with "#"
nodes_1="$(grep -v "^#" "${cnf_map_file}")"

# If needed, extract only the lines which mention direct neighboring nodes
if [ ${cnf_only_one_hop} -gt 0 ]; then
    nodes_2="$(grep "${cnf_my_ip}" <<< "${nodes_1}")"
else
    nodes_2=${nodes_1}
fi

# Cleanup the input from the network map file:
# Remove this node's own ip
nodes_3="${nodes_2//${cnf_my_ip}/}"
# And replace the commas with whitespace, so it's possible to loop over the data
nodes="${nodes_3//,/ }"

network_test_log_stdout "Nodes:\n${nodes}"

# Repeat the test for the configured number of times
for i in $(seq 1 ${cnf_repeat_count})
do
    network_test_log_stdout "Iteration ${i} of ${cnf_repeat_count}"
    
    # Loop over the nodes
    for node in ${nodes}
    do
	network_test_log_stdout "Node: ${node}"

	# Make sure the log files for this node already exist
	if [ ! -f "${cnf_log_folder}/${cnf_my_ip}-${node}-ping.csv" ]; then
	    # If not, create them and write the CSV headers at the top
	    echo "Date,Ping,Latency" > "${cnf_log_folder}/${cnf_my_ip}-${node}-ping.csv"
	fi
	if [ ! -f "${cnf_log_folder}/${cnf_my_ip}-${node}-download.csv" ]; then
	    # If not, create them and write the CSV headers at the top
	    echo "Date,Ping,Latency" > "${cnf_log_folder}/${cnf_my_ip}-${node}-download.csv"
	fi
	if [ ! -f "${cnf_log_folder}/${cnf_my_ip}-${node}-upload.csv" ]; then
	    # If not, create them and write the CSV headers at the top
	    echo "Date,Ping,Latency" > "${cnf_log_folder}/${cnf_my_ip}-${node}-upload.csv"
	fi
	
	# Test connection to this node

	# Check if we have to do ping test
	if [ ${cnf_run_ping} -gt 0 ]; then

	    if [ "${node}" == "internet" ]; then
		# If this node is the internet, then ping the ip specified in the configuration
		ping_ip="${cnf_ping_internet_ip}"
		network_test_log_stdout "Using ip ${ping_ip} for ping test"
	    else
		# Otherwise the ip mentioned in the network map file
		ping_ip="${node}"
	    fi

	    # Run the ping
	    ping_output="$(ping -c 1 ${ping_ip})"
	    ping_retval=${?}
	    if [ ${ping_retval} -eq 0 ]; then
		# If the ping was successful, extract the latency value from ping's output
		ping_latency="$(tr " " "\n" <<< "${ping_output}" | grep "time=" | tr -d "time=")"
	    else
		# Otherwise, we'll set the latency value to 0
		ping_latency="0"
	    fi

	    network_test_log_stdout "ping return value: ${ping_retval}, ping latency: ${ping_latency}"

	    # Write to the log file
	    log_file_out="$(date "+%a %d %b %H:%M:%S IST %Y"),${ping_retval},${ping_latency}"
	    echo "${log_file_out}" >> "${cnf_log_folder}/${cnf_my_ip}-${node}-ping.csv"
	    sleep 1
	fi

	# Check if we have to do speed test
	if [ ${cnf_run_speedtest} -gt 0 ]; then
	    
	    if [ "${node}" == "internet" ]; then
		# If this node is the internet, then we use the 'speedtest' command to do the test
		network_test_log_stdout "Internet speedtest"

		# Run the speed test
		speedtest_output="$(speedtest --simple)"
		speedtest_retval=${?}
		if [ ${speedtest_retval} -eq 0 ]; then
		    # If the speed test was successful, extract the download and upload values from speedtest's output
		    downspeed="$(grep "Download: " <<< "${speedtest_output}" | tr -d "Download: " | tr -d " Mbit/s")"
		    upspeed="$(grep "Upload: " <<< "${speedtest_output}" | tr -d "Upload: " | tr -d " Mbit/s")"
		else
		    # Otherwise, we'll set the download/upload values to 0
		    downspeed="0"
		    upspeed="0"
		fi
		network_test_log_stdout "speedtest return value: ${speedtest_retval}, download speed: ${downspeed}, upload speed: ${upspeed}"
		retval="${speedtest_retval}"
	    else
		# If this is a local node, then we use the 'iperf' command to do the test
		network_test_log_stdout "Local speedtest"

		# Run the speed test
		iperf_output="$(iperf -c ${node} -fm -t2)"
		iperf_retval=${?}
		if [ ${iperf_retval} -eq 0 ]; then
		    # If the speed test was successful, extract the download and upload values from iperf's output
		    # @@@ NOTE: iperf hangs if it tries to connect to a device that does not have iperf server running. iperf seems to always return 0, even in case of failure
		    downspeed="$(tr " " "\n" <<< "${iperf_output}" | grep -B 1 "Mbits/sec" | grep -v "Mbits/sec" | tail -n 1)"
		    upspeed="$(tr " " "\n" <<< "${iperf_output}" | grep -B 1 "Mbits/sec" | grep -v "Mbits/sec" | head -n 1)"
		else
		    # Otherwise, we'll set the download/upload values to 0
		    downspeed="0"
		    upspeed="0"
		fi
		network_test_log_stdout "iperf return value: ${iperf_retval}, download speed: ${downspeed}, upload speed: ${upspeed}"
		retval="${iperf_retval}"
	    fi

	    # Write to the log files
	    log_file_out="$(date "+%a %d %b %H:%M:%S IST %Y"),${retval},${downspeed}"
	    echo "${log_file_out}" >> "${cnf_log_folder}/${cnf_my_ip}-${node}-download.csv"
	    log_file_out="$(date "+%a %d %b %H:%M:%S IST %Y"),${retval},${upspeed}"
	    echo "${log_file_out}" >> "${cnf_log_folder}/${cnf_my_ip}-${node}-upload.csv"
	fi
    done
done

network_test_log_stdout "Done"

exit 0;
