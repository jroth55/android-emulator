#!/bin/bash
set -e

# Default user/group IDs and username
USER_ID=${LOCAL_USER_ID:-1000}
GROUP_ID=${LOCAL_GROUP_ID:-1000}
USER_NAME=androiduser

echo "Starting with UID: $USER_ID, GID: $GROUP_ID"

# Create user and group if they don't exist
if ! getent group $GROUP_ID > /dev/null 2>&1; then
    groupadd -f -g $GROUP_ID $USER_NAME
fi
if ! getent passwd $USER_ID > /dev/null 2>&1; then
    useradd -m -u $USER_ID -g $GROUP_ID -s /bin/bash $USER_NAME
fi
export HOME=/home/$USER_NAME

# Set the password for the androiduser (for RDP login)
if [ -n "${RDP_USER_PASSWORD}" ]; then
    echo "${USER_NAME}:${RDP_USER_PASSWORD}" | chpasswd
    echo "Password set for user ${USER_NAME}"
else
    echo "Warning: RDP_USER_PASSWORD not set. RDP login may fail."
fi

# Set the password for the root user (if ROOT_PASSWORD is provided)
if [ -n "${ROOT_PASSWORD}" ]; then
    echo "root:${ROOT_PASSWORD}" | chpasswd
    echo "Password set for user root"
else
    echo "Info: ROOT_PASSWORD not set. Root password remains unset/locked."
fi

# Prepare .xsession file for xrdp
cp /.xsession $HOME/.xsession
chmod +x $HOME/.xsession
chown $USER_ID:$GROUP_ID $HOME/.xsession

# Fix potential permission issues in home created by useradd -m
chown -R $USER_ID:$GROUP_ID $HOME

# Start xrdp services in the background
# xrdp requires DBus to be running for session management
echo "Starting D-Bus system bus..."
mkdir -p /var/run/dbus
dbus-daemon --system --fork || echo "D-Bus already running or failed to start"

echo "Starting xrdp services..."
# Run xrdp main daemon
/usr/sbin/xrdp --nodaemon &
# Run xrdp session manager
/usr/sbin/xrdp-sesman --nodaemon &

echo "Services started. Keeping container alive..."
# Keep the container running - RDP services run in background
sleep infinity
