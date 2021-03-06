#!/bin/bash
script_dir="/honeypot-setup-script/"

if [ -d "$script_dir" ];
then
	cp /honeypot-setup-script/scripts/iface-choice.py /tmp/iface-choice.py
else
	sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/scripts/iface-choice.py -O /tmp/iface-choice.py
fi

if [ -d "$script_dir" ];
then
	mkdir /etc/dionaea
	cp /honeypot-setup-script/templates/dionaea.conf.tmpl /etc/dionaea/dionaea.conf

	cp /honeypot-setup-script/templates/kippo.cfg.tmpl /tmp/kippo.cfg
else
	sudo mkdir /etc/dionaea
	sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/templates/dionaea.conf.tmpl -O /etc/dionaea/dionaea.conf

	sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/templates/kippo.cfg.tmpl -O /tmp/kippo.cfg
fi

if [ $(dpkg-query -W -f='${Status}' sudo 2>/dev/null | grep -c "ok installed") -eq 0 ]
then
  #sudo package is not currently installed on this box
  echo '[Error] Please install sudo before contniuing (apt-get install sudo)'
  exit 1
fi

current_user=$(whoami)

if [ $(sudo -n -l -U ${current_user} 2>&1 | egrep -c -i "not allowed to run sudo|unknown user") -eq 1 ]
then
   echo '[Error]: You need to run this script under an account that has access to sudo'
   exit 1
fi


# update apt repositories
echo '[apt-get] Update on current repositories'
sudo apt-get update &> /dev/null

#user iface choice
echo '[apt-get] Installing python-pip gcc python-dev'
sudo apt-get update &> /dev/null
sudo apt-get -y install python-pip gcc python-dev &> /dev/null
sudo pip install netifaces


python /tmp/iface-choice.py "$@"
iface=$(<~/.honey_iface)


# Move SSH server from Port 22 to Port 66534
sudo sed -i 's:Port 22:Port 65534:g' /etc/ssh/sshd_config
sudo service ssh reload


## install p0f ##
echo '[apt-get] Installing p0f'
sudo apt-get install -y p0f  &> /dev/null
sudo mkdir /var/p0f/

# dependency for add-apt-repository
echo '[apt-get] Installing python-software-properties'
sudo apt-get install -y python-software-properties &> /dev/null

## install glastoph ##
sudo apt-get install python2.7 python-openssl python-gevent libevent-dev python2.7-dev build-essential make
sudo apt-get install python-chardet python-requests python-sqlalchemy python-lxml
sudo apt-get install python-beautifulsoup mongodb python-pip python-dev python-setuptools
sudo apt-get install g++ git php5 php5-dev liblapack-dev gfortran libmysqlclient-dev
sudo apt-get install libxml2-dev libxslt-dev
sudo pip install --upgrade distribute

## install php sandbox ##
cd /opt
sudo git clone git://github.com/mushorg/BFR.git
cd BFR
sudo phpize
sudo ./configure --enable-bfr
sudo make && sudo make install

cd /opt
sudo git clone https://github.com/mushorg/glastopf.git
cd glastopf
sudo python setup.py install

cd /opt
sudo mkdir myhoneypot
cd myhoneypot
sudo glastopf-runner

## install dionaea ##

#add dionaea repo
sudo add-apt-repository -y ppa:honeynet/nightly
echo '[apt-get] Updating source list and installing dionaea-phibo'
{
sudo apt-get update 
sudo apt-get install -y dionaea-phibo
} &> /dev/null

#make directories
sudo mkdir -p /var/dionaea/wwwroot
sudo mkdir -p /var/dionaea/binaries
sudo mkdir -p /var/dionaea/log
sudo mkdir -p /var/dionaea/bistreams
sudo chown -R nobody:nogroup /var/dionaea/

#edit config
#note that we try and strip :0 and the like from interface here
sudo sed -i "s|%%IFACE%%|${iface%:*}|g" /etc/dionaea/dionaea.conf

## install kippo - we want the latest so we have to grab the source ##

#kippo dependencies
sudo apt-get install -y subversion python-dev openssl python-openssl python-pyasn1 python-twisted iptables

#install kippo to /opt/kippo
echo '[apt-get] Installing subversion python-dev openssl python-openssl python-pyasn1 python-twisted iptables'
sudo apt-get install -y subversion python-dev openssl python-openssl python-pyasn1 python-twisted iptables &> /dev/null

#install kippo to /opt/kippo
sudo mkdir /opt/kippo/
sudo git clone https://github.com/desaster/kippo.git /opt/kippo/
sudo cp /tmp/kippo.cfg /opt/kippo/

#add kippo user that can't login
sudo useradd -r -s /bin/false kippo

#set up log dirs
sudo mkdir -p /var/kippo/dl
sudo mkdir -p /var/kippo/log/tty
sudo mkdir -p /var/run/kippo

#delete old dirs to prevent confusion
sudo rm -rf /opt/kippo/dl
sudo rm -rf /opt/kippo/log

#set up permissions
sudo chown -R kippo:kippo /opt/kippo/
sudo chown -R kippo:kippo /var/kippo/
sudo chown -R kippo:kippo /var/run/kippo/

#point port 22 at port 2222 
#we should have -i $iface here but it was breaking things with virtual interfaces
sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222

#persist iptables config
sudo iptables-save > /etc/iptables.rules

#setup iptables restore script
sudo echo '#!/bin/sh' >> /etc/network/if-up.d/iptablesload 
sudo echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-up.d/iptablesload 
sudo echo 'exit 0' >> /etc/network/if-up.d/iptablesload 
#enable restore script
sudo chmod +x /etc/network/if-up.d/iptablesload 

#download init files and install them
sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/templates/p0f.init.tmpl -O /etc/init.d/p0f
sudo sed -i "s|%%IFACE%%|$iface|g" /etc/init.d/p0f

sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/init/dionaea -O /etc/init.d/dionaea
sudo wget https://raw.github.com/andrewmichaelsmith/honeypot-setup-script/master/init/kippo -O /etc/init.d/kippo
sudo wget https://raw.githubusercontent.com/matthewlevy97/honeypot-setup-script/master/init/glastoph -O /etc/init.d/glastoph

#install system services
sudo chmod +x /etc/init.d/p0f
sudo chmod +x /etc/init.d/dionaea
sudo chmod +x /etc/init.d/kippo
sudo chmod +x /etc/init.d/glastoph

sudo update-rc.d p0f defaults
sudo update-rc.d dionaea defaults
sudo update-rc.d kippo defaults
sudo update-rc.d glastoph defaults

#start the honeypot software
sudo /etc/init.d/kippo start
sudo /etc/init.d/p0f start
sudo /etc/init.d/dionaea start
sudo /etc/init.d/glastoph start
