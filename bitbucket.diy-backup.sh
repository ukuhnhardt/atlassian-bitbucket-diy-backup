#!/bin/bash

SCRIPT_DIR=$(dirname $0)

# Contains util functions (bail, info, print)
source ${SCRIPT_DIR}/bitbucket.diy-backup.utils.sh

# BACKUP_VARS_FILE - allows override for bitbucket.diy-backup.vars.sh
if [ -z "${BACKUP_VARS_FILE}" ]; then
    BACKUP_VARS_FILE=${SCRIPT_DIR}/bitbucket.diy-backup.vars.sh
fi

# Declares other scripts which provide required backup/archive functionality
# Contains all variables used by the other scripts
if [[ -f ${BACKUP_VARS_FILE} ]]; then
    source ${BACKUP_VARS_FILE}
else
    error "${BACKUP_VARS_FILE} not found"
    bail "You should create it using ${SCRIPT_DIR}/bitbucket.diy-backup.vars.sh.example as a template"
fi

# Contains common functionality related to Bitbucket (e.g.: lock/unlock instance, clean up lock files in repositories, etc)
source ${SCRIPT_DIR}/bitbucket.diy-backup.common.sh

# The following scripts contain functions which are dependent on the configuration of this bitbucket instance.
# Generally each of them exports certain functions, which can be implemented in different ways

if [ "rsync" = "${BACKUP_HOME_TYPE}" ] || [ "ebs-home" == "${BACKUP_HOME_TYPE}" ]; then
    # Exports the following functions
    #     bitbucket_prepare_home   - for preparing the filesystem for the backup
    #     bitbucket_backup_home    - for making the actual filesystem backup
    source ${SCRIPT_DIR}/bitbucket.diy-backup.${BACKUP_HOME_TYPE}.sh
else
    error "${BACKUP_HOME_TYPE} is not a supported home backup type"
    bail "Please update BACKUP_HOME_TYPE in ${BACKUP_VARS_FILE} or consider running bitbucket.diy-aws-backup.sh instead"
fi

if [ "mssql" = "${BACKUP_DATABASE_TYPE}" ] || [ "postgresql" = "${BACKUP_DATABASE_TYPE}" ] || [ "mysql" = "${BACKUP_DATABASE_TYPE}" ] \
    || [ "ebs-collocated" == "${BACKUP_DATABASE_TYPE}" ] || [ "rds" == "${BACKUP_DATABASE_TYPE}" ]; then
    # Exports the following functions
    #     bitbucket_prepare_db     - for making a backup of the DB if differential backups a possible. Can be empty
    #     bitbucket_backup_db      - for making a backup of the bitbucket DB
    source ${SCRIPT_DIR}/bitbucket.diy-backup.${BACKUP_DATABASE_TYPE}.sh
else
    error "${BACKUP_DATABASE_TYPE} is not a supported database backup type"
    bail "Please update BACKUP_DATABASE_TYPE in ${BACKUP_VARS_FILE} or consider running bitbucket.diy-aws-backup.sh instead"
fi

if [ "mssql" = "${BACKUP_DATABASE_TYPE}" ] || [ "postgresql" = "${BACKUP_DATABASE_TYPE}" ] || [ "mysql" = "${BACKUP_DATABASE_TYPE}" ] \
    || [ "rsync" = "${BACKUP_HOME_TYPE}" ]; then
    # Exports function bitbucket_backup_archive - for archiving the backup folder and moving the archive into archive folder
    source ${SCRIPT_DIR}/bitbucket.diy-backup.${BACKUP_ARCHIVE_TYPE}.sh
    AWS_ENABLED=false
else
    # Exports AWS specific backup functions
    source ${SCRIPT_DIR}/bitbucket.diy-backup.ec2-common.sh
    AWS_ENABLED=true
fi

##########################################################
# The actual proposed backup process. It has the following steps

# Prepare the database and the filesystem for taking a backup
bitbucket_prepare_db
bitbucket_prepare_home

# If necessary, lock the bitbucket instance
bitbucket_lock

# If necessary, start an external backup and wait for instance readiness
bitbucket_backup_start
bitbucket_backup_wait

# Back up the database and filesystem in parallel, reporting progress
(bitbucket_backup_db && bitbucket_backup_progress 50) &
(bitbucket_backup_home && bitbucket_backup_progress 50) &

# Wait until home and database backups are complete
wait $(jobs -p)

# If necessary, report 100% progress back to the application
bitbucket_backup_progress 100

# Unlocking the bitbucket instance
bitbucket_unlock

success "Successfully completed the backup of your ${PRODUCT} instance"

if [ "$AWS_ENABLED" = true ] ; then
    # Clean up old backups, keeping just the most recent ${KEEP_BACKUPS} snapshots
    cleanup_old_db_snapshots
    cleanup_old_home_snapshots
else
    # Making an archive for this backup
    bitbucket_backup_archive
fi