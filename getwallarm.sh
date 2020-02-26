#!/bin/sh
# 
# The script can be used to quickly deploy and configure a Wallarm WAF node on a supported Linux OS.
#

# Exit immediately on an error
set -e

# The name of the script - used for tagging of syslog messages
TAG="getwallarm.sh"

# Log a message to the console and syslog.
log_message() {
	SEVERITY=$1
	MESSAGE=$2
	echo `date`: $SEVERITY "$MESSAGE"
	logger -t $TAG $SEVERITY "$MESSAGE"
}

usage() {
	echo "Usage: 
	chmod u+x `basename $0`
	sudo ./`basename $0`

	Supported parameters (all the parameters are optional):
		-h
			This help message.
		-S <SITE_NAME>
			The name of used Wallarm site: EU or US1 (by default the script uses EU site).
		-u <DEPLOY_USER>
			The username to be used for the new node registration process.
		-p <DEPLOY_PASSWORD>
			The password to be used for the new node registration process.
		-n <NODE_MAME>
			The name of the node as it will visible in the Wallarm console UI (by 
			default the script will use the host name).
		-d <DOMAIN_NAME>
			The WAF reverse proxy will be configured to handle traffic for the domain.
		-o <ORIGIN_SERVER>
			The WAF reverse proxy will be configured to send upstream requests to the
			specified IP address or domain name."
}

check_if_root() {
	log_message INFO "Checking whether the script runs as root..."
	if [ "$(id -u)" -ne 0 ]; then
		log_message ERROR "This script must be executed with root permissions" 
		exit 1
	fi
}

disable_selinux() {
        log_message INFO "Checking whether SELinux is installed (and disabling it if it installed)..."
        SELINUXENABLED=`which selinuxenabled`
        SETENFORCE=`which setenforce`
        if [ -z "$SELINUXENABLED" ]; then
                log_message INFO "Cannot find 'selinuxenabled' binary - it looks like SELinux is not installed on the server."
                return
        fi

        if [ -z "$SETENFORCE" ]; then
                log_message WARNING "Cannot find 'setenforce' tool - will not try to disabled SELinux..."
                return
        fi

        log_message INFO "Running 'setenforce' command to temporary disable SELinux..."
        setenforce 0

        SELINUX_CONF=/etc/selinux/config
        if [ -f $SELINUX_CONF ]; then
                log_message INFO "Updating file $SELINUX_CONF to permanently disable SELinux..."
                sed -i 's/enforcing/disabled/g' $SELINUX_CONF
        fi
}

get_distro() {
	log_message INFO "Discovering the used operating system..." 
	lsb_dist=""
	osrelease=""
	pretty_name=""
	basearch=""

	# Every system that we support has /etc/os-release or not?
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
		osrelease="$(. /etc/os-release && echo "$VERSION_ID")"
		if [ $osrelease = "8" ]; then
			pretty_name="jessie"
		elif [ $osrelease = 9 ]; then
			pretty_name="stretch"
		elif [ $osrelease = 10 ]; then
			pretty_name="buster"
		elif [ $osrelease = 14.04 ]; then
			pretty_name="trusty"
		elif [ $osrelease = 16.04 ]; then
			pretty_name="xenial"
		elif [ $osrelease = 18.04 ]; then
			pretty_name="bionic"
		elif [ $osrelease = 7 ]; then
			pretty_name="centos"
			lsb_dist="$( rpm -qa \centos-release | cut -d"-" -f1 )"
			osrelease="$( rpm -qa \centos-release | cut -d"-" -f3 )"
			basearch=$(rpm -q --qf "%{arch}" -f /etc/$distro)
		else
			log_message ERROR "It looks like Wallarm does not support your OS. Detected OS details: osrelease = \"$osrelease\""
			exit 1
		fi

	elif [ -r /etc/centos-release ]; then
		lsb_dist="$( rpm -qa \centos-release | cut -d"-" -f1 )"
		osrelease="$( rpm -qa \centos-release | cut -d"-" -f3 )"
		basearch=$(rpm -q --qf "%{arch}" -f /etc/$distro)
	else
		log_message ERROR "It looks like Wallarm does not support your OS. Detected OS details: osrelease = \"$osrelease\""
		exit 1
	fi 


	log_message INFO "Detected OS details: lsb_dist=$lsb_dist, osrelease=$osrelease, pretty_name=$pretty_name, basearch=$basearch"
}

#install 
do_install() {

	#do some platform detection
	get_distro

	#install nginx    

	case $lsb_dist in
		debian|ubuntu)
			log_message INFO "Configuring official Nginx repository key..."
			apt-get update && apt-get install wget apt-transport-https dirmngr -y
			wget -O nginx_signing.key https://nginx.org/keys/nginx_signing.key
			apt-key add nginx_signing.key

			log_message INFO "Configuring official Nginx repository..."
			sh -c "echo 'deb https://nginx.org/packages/$lsb_dist/ $pretty_name nginx'\
				> /etc/apt/sources.list.d/nginx.list"
			sh -c "echo 'deb-src https://nginx.org/packages/$lsb_dist/ $pretty_name nginx'\
				>> /etc/apt/sources.list.d/nginx.list"

			log_message INFO "Removing nginx-common package..." 
			apt-get remove nginx-common

			log_message INFO "Installing official Nginx package..."
			apt-get update
			apt-get install -y nginx

			log_message INFO "Adding Wallarm repository key..."
			apt-key adv --keyserver keys.gnupg.net --recv-keys 72B865FD
			log_message INFO "Configuring Wallarm repository..."
			sh -c "echo 'deb http://repo.wallarm.com/$lsb_dist/wallarm-node\
				$pretty_name/'\
				>/etc/apt/sources.list.d/wallarm.list"
			apt-get update

			log_message INFO "Installing Wallarm packages..."
			apt-get install -y --no-install-recommends wallarm-node nginx-module-wallarm

			;;
		centos)
			log_message INFO "Configuring official Nginx repository..."
			echo "[nginx]" > /etc/yum.repos.d/nginx.repo
			echo "name=nginx repo" >> /etc/yum.repos.d/nginx.repo
			echo "baseurl=https://nginx.org/packages/centos/$osrelease/$basearch/" >> /etc/yum.repos.d/nginx.repo
			echo "gpgcheck=0" >> /etc/yum.repos.d/nginx.repo
			echo "enabled=1" >> /etc/yum.repos.d/nginx.repo

			log_message INFO "Installing official Nginx packages..."
			yum update -y
			if ! rpm --quiet -q nginx; then
				yum install nginx -y
			fi

			log_message INFO "Configuring Wallarm repository..."
			case $osrelease in
				6)
					if ! rpm --quiet -q epel-release; then
						yum install --enablerepo=extras -y epel-release centos-release-SCL
					fi
					if ! rpm --quiet -q wallarm-node-repo; then
						rpm -i https://repo.wallarm.com/centos/wallarm-node/6/2.14/x86_64/Packages/wallarm-node-repo-1-4.el6.noarch.rpm
					fi
					;;
				7)
					if ! rpm --quiet -q epel-release; then
						yum install -y epel-release
					fi
					if ! rpm --quiet -q wallarm-node-repo; then
						rpm -i https://repo.wallarm.com/centos/wallarm-node/7/2.14/x86_64/Packages/wallarm-node-repo-1-4.el7.noarch.rpm
					fi
					;;
			esac

			log_message INFO "Installing Wallarm packages..."
			yum update -y
			if ! rpm --quiet -q wallarm-node; then
				yum install -y wallarm-node nginx-module-wallarm
			fi

			;;
	esac

	NGINX_CONF=/etc/nginx/nginx.conf
	log_message INFO "Checking whether $NGINX_CONF is already configured to load the Wallarm module..."

	if grep -q ngx_http_wallarm_module.so $NGINX_CONF; then
		log_message INFO "It looks like the file is already configured to load the module."
	else
		log_message INFO "Updating $NGINX_CONF to load Wallarm Nginx module..."
		sed -i '/worker_processes.*/a load_module modules/ngx_http_wallarm_module.so;' /etc/nginx/nginx.conf
	fi

	CONF_DIR=/etc/nginx/conf.d/
	if [ -f $CONF_DIR/wallarm.conf -o -f $CONF_DIR/wallarm-status.conf ]; then
		log_message INFO "It looks like default Wallarm configuration files alredy present in $CONF_DIR directory."
	else
		log_message INFO "Copying default Wallarm configuration files to $CONF_DIR directory..."
		cp /usr/share/doc/nginx-module-wallarm/examples/*.conf $CONF_DIR
	fi

	log_message INFO "Enabling Nginx to launch automatically during the server startup sequence..."
	systemctl enable nginx
}

# 
# Add the node the the cloud
#
add_node() {
	log_message INFO "Working on connecting the node to the Wallarm cloud..."

	NODE_CONF=/etc/wallarm/node.yaml
	if [ -f $NODE_CONF ]; then
		log_message INFO "File $NODE_CONF already exists - skipping the node provisioning step..."
		return
	fi

	if [ -z "$API_USERNAME" ]; then
		log_message INFO "Wallarm API credentials are specified as -u and -p parameters of the script - skipping the node provisioning step."
		return
	fi

	ADDNODE_SCRIPT=/usr/share/wallarm-common/addnode
	if [ ! -x $ADDNODE_SCRIPT ]; then
		log_message ERROR "Expected script $ADDNODE_SCRIPT is not present - something is wrong with Wallarm packages - aborting."
       		exit 1
	fi

	log_message INFO "Running $ADDNODE_SCRIPT script to add the new to the Wallarm cloud (API endpoint $API_HOST)..."
	$ADDNODE_SCRIPT --force -H $API_HOST --username $API_USERNAME --password $API_PASSWORD --name $MY_NODE_NAME
}

#
# Configure the Nginx to handle the specified domain in reverse proxy mode
#
configure_proxy() {
	log_message INFO "Checking whether we need to configure the Nginx proxy..."
	CONF_FILE=/etc/nginx/conf.d/wallarm-proxy.conf	
	if [ -f $CONF_FILE ]; then
		log_message INFO "Nginx configuration file $CONF_FILE already present - skipping the proxy configuration process..."
		return
	fi

	if [ -z "$DOMAIN_NAME" ]; then
		log_message INFO "Script parameter -d is not specified - skipping the proxy configuration step..."
		return
	fi

	if [ -z "$ORIGIN_NAME" ]; then
		log_message INFO "Origin address is not specified (script option -o) - using domain name $DOMAIN_NAME"
		ORIGIN_NAME=$DOMAIN_NAME
	fi

	log_message INFO "Creating Nginx configuration file $CONF_FILE with settings for domain $DOMAIN_NAME and origin address $ORIGIN_NAME..."

cat > $CONF_FILE << EOF

# Set global Wallarm WAF mode to "block"
wallarm_mode block;

server {
  listen       80;
  # the domains for which traffic is processed
  server_name $DOMAIN_NAME

  # turn on the Wallarm WAF blocking mode
  wallarm_mode block;
  # wallarm_mode monitoring; 
  # wallarm_instance 1;

  location / {
    # setting the address for request forwarding
    proxy_pass http://$ORIGIN_NAME;
    proxy_set_header Host $DOMAIN_NAME;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}

EOF

	log_message INFO "Using 'nginx -t' command verifying that the Nginx configuration is correct..."
	if ! nginx -t; then
		log_message ERROR "It looks like Nginx doesn't like the new configuration - aborting."
		exit 1
	fi

        log_message INFO "Starting the Nginx service (just in case if it is not running)..."
        service nginx start

	log_message INFO "Reloading Nginx configuration..."
	service nginx reload

}

#
# Send a few test requests
#
test_proxy() {
	log_message INFO "Sending a request to Wallarm WAF status page http://127.0.0.8/wallarm-status..."
	curl http://127.0.0.8/wallarm-status

	if [ -z "$DOMAIN_NAME" ]; then
		log_message INFO "The domain name is not specified - skipping the domain testing step..."
		return
	fi
	log_message INFO "Sending a regular HTTP request to the localhost for domain $DOMAIN_NAME..."
	curl -v -H "Host: $DOMAIN_NAME" http://localhost/ > /dev/null

	log_message INFO "Sending a malicious HTTP request to the localhost for domain $DOMAIN_NAME (the response code should be 403)..."
	curl -v -H "Host: $DOMAIN_NAME" "http://localhost/?id='or+1=1--a-<script>prompt(1)</script>" > /dev/null
}

# By default use the Wallarm EU site
API_SITE=eu

MY_NODE_NAME=`hostname`

while getopts :hu:p:d:o:n:S: option
do
	case "$option" in
		h)
			usage;
			exit 1
			;;
		u)
			# Wallarm username for WAF node registration
			API_USERNAME=$OPTARG;
			;;
		p)
			# Wallarm password for WAF node registration
			API_PASSWORD=$OPTARG;
			;;
		n)
			# The name of the node
			MY_NODE_NAME=$OPTARG;
			;;
		d)
			# Domain name as recognized by this node and the origin server
			DOMAIN_NAME=$OPTARG;
			;;
		o)
			# IP address or DNS name of the origin server
			ORIGIN_NAME=$OPTARG;
			;;
		S)	
			# API site name (EU or US1)
			API_SITE=`echo $OPTARG | tr '[:upper:]' '[:lower:]'`;
			;;
		*)
			echo "Hmm, an invalid option was received."
			usage
			exit 1
			;;
	esac
done

if [ ! -z "$API_USERNAME" -a -z "$API_PASSWORD" ]; then
	log_message ERROR "Please specify both username and password parameters."
	usage
	exit 1
fi

if [ "$API_SITE" = "us1" ]; then
	API_HOST=us1.api.wallarm.com
elif [ "$API_SITE" = "eu" ]; then
	API_HOST=api.wallarm.com
else
	log_message ERROR "Unknown Wallarm site name \"$API_SITE\". Accepted Wallarm site names are EU and US1. Aborting."
	usage
	exit 1
fi

check_if_root

disable_selinux

do_install

add_node

configure_proxy

test_proxy

log_message INFO "We've completed the Wallarm WAF node deployment process."
