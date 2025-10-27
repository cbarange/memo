# Backup Managment with a MySQL
[![ViewCount](https://views.whatilearened.today/views/github/cbarange/memo-backup-managment-with-a-mysql.svg)](https://views.whatilearened.today/views/github/cbarange/memo-backup-managment-with-a-mysql.svg)

> cbarange | 3th Feb 2022
---

> You will need gen-backup.sh and obfuscate.sql file to run to generate the normal and the obfuscate backup. Please found them in this folder. 

The goal is to generate daily backups and upload them to a sftp server. There is a normal backup and a obfuscated one. The normal is use to keep the data safely and the obfuscated is here to allow the devlopper to download a fresh database
without having the critical data loaded.
