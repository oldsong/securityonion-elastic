#!/bin/bash
# Convert Security Onion ELSA to Elastic

# Check for prerequisites
if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run using sudo!"
        exit 1
fi

# Make a directory to store downloads
DIR="/opt/elastic"
PCAP_DIR="$DIR/pcap"
mkdir -p $PCAP_DIR
cd $DIR

# Define a banner to separate sections
banner="========================================================================="

header() {
        echo
        printf '%s\n' "$banner" "$*" "$banner"
}

REPO="elastic-test"
if [ "$1" == "dev" ]; then
        URL="https://github.com/dougburks/$REPO.git"
        DOCKERHUB="dougburks"
else
        URL="https://github.com/Security-Onion-Solutions/$REPO.git"
        DOCKERHUB="securityonionsolutions"
fi
EOF

clear
cat << EOF 
This QUICK and DIRTY script is designed to allow you to quickly and easily experiment with the Elastic stack (Elasticsearch, Logstash, and Kibana) on Security Onion.

This script assumes that you've already installed the latest Security Onion 14.04.5.2 ISO image as follows:
* (1) management interface with full Internet access
* (1) sniffing interface (separate from management interface)

This script will do the following:
* install Docker and download Docker images for Elasticsearch, Logstash, and Kibana
* import our custom visualizations and dashboards
* configure syslog-ng to send logs to Logstash on port 6050
* configure Apache as a reverse proxy for Kibana and authenticate users against Sguil database
* update CapMe to leverage that single sign on (SSO) and integrate with Elasticsearch
* update Squert to use SSO
* replay sample pcaps to provide data for testing

Depending on the speed of your hardware and Internet connection, this process will take at least 10 minutes.

TODO
For the current TODO list, please see:
https://github.com/Security-Onion-Solutions/security-onion/issues/1095

HARDWARE REQUIREMENTS
The Elastic stack requires more hardware than ELSA.  For best results on your test VM, you'll probably want at LEAST 2 CPU cores and 8GB of RAM.

THANKS
Special thanks to Justin Henderson for his Logstash configs and installation guide!
https://github.com/SMAPPER/Logstash-Configs

Special thanks to Phil Hagen for all his work on SOF-ELK!
https://github.com/philhagen/sof-elk

WARNINGS AND DISCLAIMERS
* This technology PREVIEW is PRE-ALPHA, BLEEDING EDGE, and TOTALLY UNSUPPORTED!
* If this breaks your system, you get to keep both pieces!
* This script is a work in progress and is in constant flux.
* This script is intended to build a quick prototype proof of concept so you can see what our ultimate Elastic configuration might look like.  This configuration will change drastically over time leading up to the final release.
* Do NOT run this on a system that you care about!
* Do NOT run this on a system that has data that you care about!
* This script should only be run on a TEST box with TEST data!
* This script is only designed for standalone boxes and does NOT support distributed deployments.
* Use of this script may result in nausea, vomiting, or a burning sensation.
 
Once you've read all of the WARNINGS AND DISCLAIMERS above, please type AGREE to proceed:
EOF
read INPUT
if [ "$INPUT" != "AGREE" ] ; then exit 0; fi

header "Installing git and libapache2-mod-authnz-external"
apt-get update > /dev/null
apt-get install -y git libapache2-mod-authnz-external > /dev/null
echo "Done!"

header "Downloading files"
git clone $URL
cp -av $REPO/usr/sbin/* /usr/sbin/
chmod +x /usr/sbin/so-elastic-*
echo "Done!"

. /usr/sbin/so-elastic-download

/usr/sbin/sosetup

if [ -f /etc/nsm/sensortab ]; then
	NUM_INTERFACES=`grep -v "^#" /etc/nsm/sensortab | wc -l`
	if [ $NUM_INTERFACES -gt 0 ]; then
		SECONDS=120
		header "Waiting $SECONDS seconds to allow Logstash to initialize"
		# This check for logstash isn't working correctly right now.
		# I think docker-proxy is completing the 3WHS and making nc think that logstash is up before it actually is.
		#max_wait=240
		#wait_step=0
		#until nc -vz localhost 6050 > /dev/null 2>&1 ; do
		#	wait_step=$(( ${wait_step} + 1 ))
		#	if [ ${wait_step} -gt ${max_wait} ]; then
		#		echo "ERROR: logstash not available for more than ${max_wait} seconds."
		#		exit 5
		#	fi
		#	sleep 1;
		#	echo -n "."
		#done
		#echo
		for i in `seq 1 $SECONDS`; do
			sleep 1s
			echo -n "."
		done
		echo

		header "Replaying pcaps to create new logs for testing"
		INTERFACE=`grep -v "^#" /etc/nsm/sensortab | head -1 | awk '{print $4}'`
		for i in /opt/samples/*.pcap /opt/samples/markofu/*.pcap /opt/samples/mta/*.pcap $PCAP_DIR/*.trace $PCAP_DIR/*.pcap; do
			echo -n "." 
			tcpreplay -i $INTERFACE -M10 $i >/dev/null 2>&1
		done
		echo
	fi
fi

header "All done!"
cat << EOF

After a minute or two, you should be able to access Kibana via the following URL:
https://localhost/app/kibana

When prompted for username and password, use the same credentials that you use to login to Sguil and Squert.

You will automatically start on our Overview dashboard and you will see links to other dashboards as well.  These dashboards are designed to work at 1024x768 screen resolution in order to maximize compatibility.

As you search through the data in Kibana, you should see Bro logs, syslog, and Snort alerts.  Logstash should have parsed out most fields in most Bro logs and Snort alerts.

Notice that the source_ip and destination_ip fields are hyperlinked.  These hyperlinks will take you to a dashboard that will help you analyze the traffic relating to that particular IP address.

UID fields are also hyperlinked.  This hyperlink will start a new Kibana search for that particular UID.  In the case of Bro UIDs this will show you all Bro logs related to that particular connection.

Each log entry also has an _id field that is hyperlinked.  This hyperlink will take you to CapMe, allowing you to request full packet capture for any arbitrary log type!  This assumes that the log is for tcp or udp traffic that was seen by Bro and Bro recorded it correctly in its conn.log.  CapMe should try to do the following:
* retrieve the _id from Elasticsearch
* parse out timestamp
* if Bro log, parse out the CID, otherwise parse out src IP, src port, dst IP, and dst port
* query Elasticsearch for those terms and try to find the corresponding bro_conn log
* parse out sensor name (hostname-interface)
* send a request to sguild to request pcap from that sensor name

Previously, in Squert, you could pivot from an IP address to ELSA.  That pivot has been removed and replaced with a pivot to Kibana.

Happy Hunting!

EOF
