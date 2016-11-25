#!/bin/bash

#-----------------
#set init variable
#-----------------
#check if user is the root
if (( EUID != 0 )); then
   echo "You need the root access to execute this script. Sorry ;)" 1>&2
   exit 100
fi
user=$(whoami)

#Get vhost nad user names
echo -n  "Vhost address: "
read vh
domain=${vh##*.}
sitename=${vh%*.$domain}
echo -n "User with access permission to this vhost (default: $user ): "
read vhowner

echo -n "Vhost path [/var/www/]: "
read vp

#Check if vhost exists
if ( grep -qi $vh /etc/hosts ); then
	echo "$(tput setaf 1)Such vhost exists.$(tput sgr 0) Please choose a different address"
	exit 1
fi

#input validation
if [ -z $sitename ]; then
	echo "$(tput setaf 1)Sorry, but site name can't be empty.$(tput sgr 0) Try again."
	exit 1
fi

if [ -z $domain ]; then
	echo "$(tput setaf 1)Sorry, but domain name can't be empty.$(tput sgr 0) Try again."
    exit 1
fi

if [ -z $vhowner ]; then
  #if user prompt is empty get current sustem user name
  vhowner=${user}
fi

if [ -z $vp  ]; then
	#if path is empty set default /var/www/
	vp="/var/www/"
fi

#----------------------------
#prepare director environment
#----------------------------
#make vhost directory
mkdir -p $vp$vh

#change owner
chown -R $vhowner:www-data $vp$sitename.$domain

#logs
mkdir /var/log/apache2/$vh/

#---------------------------
#vhost configuration - START
#---------------------------
echo "<VirtualHost *:80>
 DocumentRoot $vp$vh/
 ServerName $vh
 ServerAlias $vh www.$vh
 <Directory $vp$vh/ >
  Options Indexes FollowSymLinks
  AllowOverride All
  Require all granted
 </Directory>

 #plik z logami
 ErrorLog /var/log/apache2/$vh/error.log
 LogLevel warn
 CustomLog /var/log/apache2/$vh/access.log combined
</VirtualHost>" > "/etc/apache2/sites-available/$vh.conf"

echo  127.0.0.1    $vh >>/etc/hosts
echo  127.0.0.1    www.$vh >>/etc/hosts

#enable vhost
a2ensite $vh

/etc/init.d/apache2 restart

echo -e "$(tput setaf 2)New vhost $vh has been created!$(tput sgr 0) \n"

#----------------------
#database setup - START
#----------------------
read -p "Do you want to create database? [y / n] " -n 1 -r
#confirmation to create database
if ([[ $REPLY =~ ^[Yy]$ ]]) then
	#echo -e "\n"
	#echo -n "MySQL  user with create/drop database privilages : "
	#read dbuser

	#echo -n "\n MySQL user's password: "
	#read dbuserpass

	mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS $sitename;
	CREATE USER '$sitename'@'localhost' IDENTIFIED BY 'admin';
	GRANT ALL PRIVILEGES ON * . * TO '$sitename'@'localhost';
	FLUSH PRIVILEGES;"

	echo -e "$(tput setaf 2)New database $sitename has been created!$(tput sgr 0)"
fi

#--------------------------------
#drupal environment setup - START
#--------------------------------
#Check if Drush is installed
if ! type -p drush > /dev/null; then
  echo -n 'Drush is not installed'
  echo -n 'Installing Drush'
  pear channel-discover pear.drush.org
  pear install drush/drush
fi

cd $vp$vh

echo 'Downloading Drupal and most useful modules...'
#Download Drupal with modules which have defined in .make files
drush -y  make https://raw.github.com/fadehelix/DrupalDevelopmentScripts/master/drush/default.make .

#files
mkdir sites/default/files
chmod -R  g+w sites/default/files/

#prepare settings
cp sites/default/default.settings.php sites/default/settings.php
chmod g+w sites/default/settings.php

#install drupal
drush si standard --account-name=admin account-pass='admin' --db-url=mysql://"$sitename":"admin"@localhost/"$sitename" -y

echo -e "\n\n $(tput setaf 6)Success!$(tput sgr 0) \n " 




