#!/bin/bash

check_command "rsync"

function prepare_backup_home {
    perform_rsync
    info "Prepared backup of ${BITBUCKET_HOME} to ${BITBUCKET_BACKUP_HOME}"
}

function backup_home {
    perform_rsync
    info "Performed backup of ${BITBUCKET_HOME} to ${BITBUCKET_BACKUP_HOME}"
}

function prepare_restore_home {
    no_op
}

function restore_home {
    local rsync_quiet=-q
    if [ "${BITBUCKET_VERBOSE_BACKUP}" = "TRUE" ]; then
        rsync_quiet=
    fi

    rsync -av ${rsync_quiet} ${BITBUCKET_RESTORE_HOME}/ ${BITBUCKET_HOME}/
    info "Performed restore of ${BITBUCKET_RESTORE_HOME} to ${BITBUCKET_HOME}"
}

function perform_rsync {
    for repo_id in ${BITBUCKET_BACKUP_EXCLUDE_REPOS[@]}; do
      rsync_exclude_repos="${rsync_exclude_repos} --exclude=/shared/data/repositories/${repo_id}"
    done

    local rsync_quiet=-q
    if [ "${BITBUCKET_VERBOSE_BACKUP}" = "TRUE" ]; then
        rsync_quiet=
    fi

    mkdir -p ${BITBUCKET_BACKUP_HOME}
    rsync -avh ${rsync_quiet} --delete --delete-excluded --exclude=/caches/ --exclude=/shared/data/db.* \
        --exclude=/shared/search/data/ --exclude=/export/ --exclude=/log/ --exclude=/plugins/.*/ --exclude=/tmp \
        --exclude=/.lock --exclude=/shared/.lock ${rsync_exclude_repos} ${BITBUCKET_HOME} ${BITBUCKET_BACKUP_HOME}
    if [ $? != 0 ]; then
        bail "Unable to rsync from ${BITBUCKET_HOME} to ${BITBUCKET_BACKUP_HOME}"
    fi
}