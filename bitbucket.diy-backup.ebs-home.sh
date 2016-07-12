#!/bin/bash


function bitbucket_prepare_home {
    # Validate that all the configuration parameters have been provided to avoid bailing out and leaving Bitbucket locked
    if [ -z "${HOME_DIRECTORY_MOUNT_POINT}" ]; then
        error "The home directory mount point must be set as HOME_DIRECTORY_MOUNT_POINT in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${HOME_DIRECTORY_DEVICE_NAME}" ]; then
        error "The home directory volume device name must be set as HOME_DIRECTORY_DEVICE_NAME in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    BACKUP_HOME_DIRECTORY_VOLUME_ID=
    validate_ebs_volume "${HOME_DIRECTORY_DEVICE_NAME}" BACKUP_HOME_DIRECTORY_VOLUME_ID

    if [ -z "${BACKUP_HOME_DIRECTORY_VOLUME_ID}" ] || [ "${BACKUP_HOME_DIRECTORY_VOLUME_ID}" == null ]; then
        error "Device name ${HOME_DIRECTORY_DEVICE_NAME} specified in ${BACKUP_VARS_FILE} as HOME_DIRECTORY_DEVICE_NAME could not be resolved to a volume."

        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi
}

function bitbucket_backup_home {
    # Freeze the home directory filesystem to ensure consistency
    freeze_home_directory

    # Add a clean up routine to ensure we unfreeze the home directory filesystem
    add_cleanup_routine unfreeze_home_directory

    info "Performing backup of home directory"
    local EBS_SNAPSHOT_ID=$(snapshot_ebs_volume "${BACKUP_HOME_DIRECTORY_VOLUME_ID}" "Perform backup: ${PRODUCT} home directory snapshot")

    # Unfreeze the home directory as soon as the EBS snapshot has been taken
    unfreeze_home_directory

    # Optionally copy/share the EBS snapshot to another region and/or account.
    # This is useful to retain a cross region/account copy of the backup.
    if [ -n "${BACKUP_EBS_DEST_REGION}" ]; then
        if [ -n "${BACKUP_DEST_AWS_ACCOUNT_ID}" ] && [ -n "${BACKUP_DEST_AWS_ROLE}" ]; then
            copy_and_share_ebs_snapshot ${EBS_SNAPSHOT_ID} ${AWS_REGION}
        else
            copy_ebs_snapshot ${EBS_SNAPSHOT_ID} ${AWS_REGION} ${BACKUP_EBS_DEST_REGION}
        fi
    fi
}

function bitbucket_prepare_home_restore {
    local SNAPSHOT_TAG="${1}"

    if [ -z "${BITBUCKET_HOME}" ]; then
        error "The ${PRODUCT} home directory must be set as BITBUCKET_HOME in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${BITBUCKET_UID}" ]; then
        error "The ${PRODUCT} home directory owner account must be set as BITBUCKET_UID in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${AWS_AVAILABILITY_ZONE}" ]; then
        error "The availability zone for new volumes must be set as AWS_AVAILABILITY_ZONE in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${RESTORE_HOME_DIRECTORY_VOLUME_TYPE}" ]; then
        error "The type of volume to create when restoring the home directory must be set as RESTORE_HOME_DIRECTORY_VOLUME_TYPE in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    elif [ "io1" == "${RESTORE_HOME_DIRECTORY_VOLUME_TYPE}" ] && [ -z "${RESTORE_HOME_DIRECTORY_IOPS}" ]; then
        error "The provisioned iops must be set as RESTORE_HOME_DIRECTORY_IOPS in ${BACKUP_VARS_FILE} when choosing 'io1' volume type for the home directory EBS volume"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${HOME_DIRECTORY_DEVICE_NAME}" ]; then
        error "The home directory volume device name must be set as HOME_DIRECTORY_DEVICE_NAME in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    if [ -z "${HOME_DIRECTORY_MOUNT_POINT}" ]; then
        error "The home directory mount point must be set as HOME_DIRECTORY_MOUNT_POINT in ${BACKUP_VARS_FILE}"
        bail "See bitbucket.diy-aws-backup.vars.sh.example for the defaults."
    fi

    check_mount_point "${HOME_DIRECTORY_MOUNT_POINT}"

    validate_device_name "${HOME_DIRECTORY_DEVICE_NAME}"

    RESTORE_HOME_DIRECTORY_SNAPSHOT_ID=
    validate_ebs_snapshot "${SNAPSHOT_TAG}" RESTORE_HOME_DIRECTORY_SNAPSHOT_ID
}

function bitbucket_restore_home {
    unmount_device "${HOME_DIRECTORY_MOUNT_POINT}"

    detach_volume "${HOME_DIRECTORY_MOUNT_POINT}"

    info "Restoring home directory from snapshot ${RESTORE_HOME_DIRECTORY_SNAPSHOT_ID} into a ${RESTORE_HOME_DIRECTORY_VOLUME_TYPE} volume"

    create_and_attach_volume "${RESTORE_HOME_DIRECTORY_SNAPSHOT_ID}" "${RESTORE_HOME_DIRECTORY_VOLUME_TYPE}" \
            "${RESTORE_HOME_DIRECTORY_IOPS}" "${HOME_DIRECTORY_DEVICE_NAME}" "${HOME_DIRECTORY_MOUNT_POINT}"

    mount_device "${HOME_DIRECTORY_DEVICE_NAME}" "${HOME_DIRECTORY_MOUNT_POINT}"

    cleanup_locks ${BITBUCKET_HOME}

    info "Performed restore of home directory snapshot"
}

function freeze_home_directory {
    freeze_mount_point ${HOME_DIRECTORY_MOUNT_POINT}
}

function unfreeze_home_directory {
    unfreeze_mount_point ${HOME_DIRECTORY_MOUNT_POINT}
}

function cleanup_old_home_snapshots {
    for snapshot_id in $(list_old_ebs_snapshot_ids); do
        info "Deleting old EBS snapshot ${snapshot_id}"
        delete_ebs_snapshot "${snapshot_id}"
    done
}
