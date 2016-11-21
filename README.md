# oc-scripts

## Synopsis

In this repository you'll find some scripts I wrote for automating regular tasks you need to do when running an ownCloud.

## Motivation

I have been using ownCloud for quite a lot of years now. As the team behind ownCloud does a great job, I was missing an easy way to do a backup of my full ownCloud including the config, the data from the file system and of course the contents of the database.

It all started with a small three line bash script that wasn't failure proof at all and had most of the information hardcoded. When the occ command was introduced, I started playing around with it and found out that it is really helpful to automate my backups.

For a while the script grew a lot and it wasn't readable any more. Before I decided that I need to rewrite the script I had already started to change from hardcoded configurations to using parameters when calling the script. But if you have ten mandatory parameters, life doesn't get easier.

After the script looked terrible and I always messed up with the parameters, I realized that I had to rewrite the script from scratch. After doing so the backup script only has two mandatory parameters and a lot of information is fetched by using the occ command.

Besides the backup script I also wrote a script that checks if an update is available and another one which automates the process of updating your ownCloud.

## Using the scripts

### /backup/oc-backup.sh

This script does a full backup of your ownCloud. The backup contains
 * the configuration directory which contains your config.php
 * a backup of the files that are stored in your ownCloud
 * a backup of the MySQL database you use for your ownCloud

**CAUTION:** You need to run this command as the user that is used for running your ownCloud (e.g. oc-user)

| command                        | install directory | target directory  | mail recipient       | temporary directory             | 
| ------------------------------ | ----------------- | ----------------- | -------------------- | ------------------------------- |
| sudo -u oc-user ./oc-backup.sh | /var/www          | /backups/owncloud | owncloud@example.com | /tmp                            |
|                                | **mandatory**     | **mandatory**     | **mandatory**        | _optional (default /tmp)_ |

so the complete call would look like this **sudo -u \<oc-user\> \<install directory\> \<target directory\> \<mail recipient\> [\<temporary directory\>]**
