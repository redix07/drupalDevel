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
	echo -e "$(tput setaf 2)user name: $sitename and password: admin$(tput sgr 0)"
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

#get custom module
git clone https://github.com/redix07/drupalModule.git sites/all/modules/
rm -R sites/all/modules/.git

#get inir data
git clone https://github.com/redix07/drupalDataini.git sites/default/
rm -R sites/default//.git

#get base theme
git clone https://github.com/redix07/drupalTheme.git sites/all/themes/
rm -R sites/all/themes/.git

mv sites/all/themes/base-theme-name sites/all/themes/$sitename
mv sites/all/themes/$sitename/base-theme-name.info sites/all/themes/$sitename/$sitename.info
mv sites/all/themes/$sitename/base-theme-name.info sites/all/themes/$sitename/$sitename.info
mv sites/all/themes/$sitename/scss/base-theme-name.scss sites/all/themes/$sitename/scss/$sitename.scss

sed -i "s/base_theme_name/$sitename/g" sites/all/themes/$sitename/$sitename.info
sed -i "s/base_theme_name/$sitename/g" sites/all/themes/$sitename/template.php
sed -i "s/base_theme_name/$sitename/g" sites/all/themes/$sitename/theme-settings.php

sed -i "s/base_theme_name/$sitename/g" sites/all/themes/$sitename/templates/page.tpl.php
sed -i "s/base_theme_name/$sitename/g" sites/all/themes/$sitename/templates/node/node--news.tpl.php

#--------------------------------
#drupal pre Install
#--------------------------------

#get drupal core and module
echo 'Downloading Drupal and most useful modules...'
#Download Drupal with modules which have defined in .make files
drush -y  make https://raw.githubusercontent.com/redix07/drupalDevel/master/profile.make .

#files
mkdir sites/default/files
chmod -R  g+w sites/default/files/

#privfiles
chmod -R  g+w sites/default/privfiles/

#prepare settings
cp sites/default/default.settings.php sites/default/settings.php
chmod g+w sites/default/settings.php

#--------------------------------
#drupal Install
#--------------------------------

#install drupal
drush si standard --account-name=admin --account-pass='admin' --db-url=mysql://"$sitename":"admin"@localhost/"$sitename" -y

#--------------------------------
#drupal Install - add module
#--------------------------------

#Some site customization after installation
drush en admin admin_menu adminimal_admin_menu features devel backup_migrate node_export uuid field_group filefield_sources filefield_sources_plupload paragraphs jquery_update metatag metatag_hreflang metatag_views module_filter pathauto transliteration webform views views_ui colorbox base_page_setup bps_ct_base bps_views_article bps_pathauto bps_conf_lang bps_menu_top -y
drush dis toolbar -y

#---------------------------------------
#drupal Configuration and finale  config
#---------------------------------------

#Setup disable comments
drush vset comment_article 0 -y
drush vset comment_page 0 -y
drush vset comment_webform 0 -y

#Setup pathauto pattern
drush vset  pathauto_node_article_pattern 'news/[node:title].html'
drush vset  pathauto_node_page_pattern '[node:title].html'
drush vset  pathauto_node_page_webform '[node:title].html'

#Setup privfiles
drush vset --yes file_private_path sites/default/privfiles

#Setup theme
drush pm-enable $sitename -y
drush vset theme_default $sitename
drush vset admin_theme adminimal

#restore data
drush bam-restore files manual "file-data.tar.gz" -y

#--------------------------------
# add librays
#--------------------------------
cd sites/all/libraries

# plupload
wget  https://github.com/moxiecode/plupload/archive/v1.5.8.zip
unzip v1.5.8.zip
rm -R v1.5.8.zip
mv plupload-1.5.8 plupload

# plupload
wget  https://github.com/jackmoore/colorbox/archive/1.x.zip
unzip 1.x.zip
rm -R 1.x.zip
mv colorbox-1.x colorbox

cd ../../../

#--------------------------------
# SASS setup
#--------------------------------

cd sites/all/themes/$sitename/
npm install
bower install
cd ../../../../

#--------------------------------
# final setup
#--------------------------------

#change owner
chown -R $vhowner:www-data $vp$vh


echo -e "$(tput setaf 2)New vhost $vh has been created!$(tput sgr 0) \n"
echo -e "$(tput setaf 2)New database $sitename has been created!$(tput sgr 0)"
echo -e "$(tput setaf 2)user name: $sitename and password: admin$(tput sgr 0)"

echo -e "\n\n $(tput setaf 6)Success!$(tput sgr 0) \n "
