#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Starting Phase 1 Setup for Android RDP Environment (with Root Password option) ---"

# --- Create Directories ---
echo "[+] Creating 'emulator-desktop' directory..."
mkdir -p emulator-desktop
echo "    Done."

# --- Create .env File ---
echo "[+] Creating '.env' file with placeholder passwords..."
cat << EOF > .env
# --- Secrets ---
# Choose strong passwords!

# Password for the 'androiduser' to log in via RDP
RDP_USER_PASSWORD=YourSecretRdpPassword

# Password for the root user (optional, for 'su -' inside container)
ROOT_PASSWORD=YourSuperStrongSecretRootPassword
EOF
echo "    Done. IMPORTANT: Edit '.env' later to set strong passwords (but DO NOT commit it to Git)."

# --- Create emulator-desktop/.xsession File ---
echo "[+] Creating 'emulator-desktop/.xsession'..."
cat << 'EOF' > emulator-desktop/.xsession
#!/bin/sh
# Start the XFCE4 Session Manager
xfce4-session
EOF
chmod +x emulator-desktop/.xsession
echo "    Done."

# --- Create emulator-desktop/entrypoint.sh File (Updated) ---
echo "[+] Creating 'emulator-desktop/entrypoint.sh' (with root password logic)..."
cat << 'EOF' > emulator-desktop/entrypoint.sh
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
EOF
chmod +x emulator-desktop/entrypoint.sh
echo "    Done."

# --- Create emulator-desktop/Dockerfile ---
# (Dockerfile content remains the same as the previous RDP version)
echo "[+] Creating 'emulator-desktop/Dockerfile' (with SDK ADD instruction)..."
cat << 'EOF' > emulator-desktop/Dockerfile
# Use a stable Ubuntu base
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# Install base utilities, XFCE, RDP, Java, Android prerequisites
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo wget unzip curl ca-certificates dbus-daemon \
    # Desktop & RDP
    xfce4 xfce4-goodies dbus-x11 \
    xrdp \ # Install xrdp server
    # Java
    openjdk-17-jdk \
    # Android Emulator dependencies
    libnss3 libglu1-mesa libpulse0 libasound2 libxcb-cursor0 \
    # KVM (tools useful for debugging, host needs KVM anyway)
    qemu-kvm \
    # Utils
    bash-completion nano procps chpasswd \
    && apt-get upgrade -y && \ # Apply security updates
    apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Android SDK Installation ---
ENV ANDROID_SDK_ROOT /opt/android-sdk
ENV PATH $PATH:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator

# --- SDK DOWNLOAD METHOD (Manual Download + ADD) ---
# !!! IMPORTANT !!!
# Before building the Docker image, manually download the Linux command-line tools zip
# from https://developer.android.com/studio#command-line-tools-only
# and place it in the 'emulator-desktop' directory.
# Then, update the filename in the COPY command below if necessary.
# -----------------------------------------------------
COPY commandlinetools-linux-*.zip /opt/cmdline-tools.zip # Adjust wildcard/filename if needed

RUN cd /opt && \
    unzip -q cmdline-tools.zip && \
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools && \
    mv cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest && \
    rm cmdline-tools.zip
# --- End SDK DOWNLOAD METHOD ---

# Accept licenses and install core packages (Makes image larger)
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --licenses && \
    ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager \
        "platform-tools" \
        "emulator" \
        "system-images;android-33;google_apis_playstore;x86_64" # Example Image

# Grant read/execute permissions to SDK for all users
RUN chmod -R a+rX ${ANDROID_SDK_ROOT}

# Set up user/entrypoint (User ID/Group ID will be passed during build)
ARG LOCAL_USER_ID=1000
ARG LOCAL_GROUP_ID=1000
ENV LOCAL_USER_ID=$LOCAL_USER_ID
ENV LOCAL_GROUP_ID=$LOCAL_GROUP_ID

# Copy .xsession script and entrypoint
COPY .xsession /.xsession
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose RDP port (default 3389)
EXPOSE 3389

ENTRYPOINT ["/entrypoint.sh"]
EOF
echo "    Done."
echo "    !!! ACTION REQUIRED: Manually download 'commandlinetools-linux-XYZ.zip' from Google"
echo "                      and place it inside the 'emulator-desktop' directory before building!"
echo "                      Update the filename in the Dockerfile if needed."


# --- Create docker-compose.yml File (Updated) ---
echo "[+] Creating 'docker-compose.yml' (with root password env)..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  emulator-desktop:
    # Build the image from the 'emulator-desktop' directory
    build:
      context: ./emulator-desktop
      args:
        # These can be overridden in Coolify build settings if needed
        LOCAL_USER_ID: ${LOCAL_USER_ID:-1000}
        LOCAL_GROUP_ID: ${LOCAL_GROUP_ID:-1000}
    container_name: android_rdp_desktop_${COOLIFY_SERVICE_ID:-local}
    restart: unless-stopped
    # !! CRITICAL REQUIREMENT for Emulator performance !!
    # Needs KVM access from the HOST. Coolify *MUST* allow this device mapping.
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/snd:/dev/snd # Optional: for sound passthrough
      - /dev/dri:/dev/dri # Optional: needed if trying host GPU passthrough (Very Advanced)
    # Alternatively, if Coolify allows it and device mapping fails:
    # privileged: true
    volumes:
      # Mount the entire home directory for full user persistence
      - android_home_data:/home/androiduser
    environment:
      # Pass passwords from .env/Coolify Secrets
      RDP_USER_PASSWORD: ${RDP_USER_PASSWORD}
      ROOT_PASSWORD: ${ROOT_PASSWORD} # Added root password env var
    # --- PORT MAPPING ---
    # Expose the internal RDP port (3389). Coolify manages mapping to host port.
    ports:
      - "3389"

volumes:
  android_home_data:
EOF
echo "    Done."

# --- Create .gitignore File ---
echo "[+] Creating '.gitignore'..."
cat << EOF > .gitignore
.env
.DS_Store
emulator-desktop/commandlinetools-linux-*.zip
EOF
echo "    Done."

# --- Initialize Git ---
echo "[+] Initializing Git repository..."
git init
git add .
git commit -m "Initial project structure for Android RDP environment (with root pw)"
echo "    Done."

echo ""
echo "--- Phase 1 Setup Complete ---"
echo "Next Steps:"
echo "1. Edit '.env' and set strong 'RDP_USER_PASSWORD' and 'ROOT_PASSWORD'."
echo "2. Download the Android SDK Command-line Tools for Linux zip file from Google."
echo "3. Place the downloaded zip file into the 'emulator-desktop' directory."
echo "4. Verify the filename in 'emulator-desktop/Dockerfile' matches the downloaded zip."
echo "5. Create a repository on GitHub/GitLab and push this code:"
echo "   git remote add origin <your-repository-url>"
echo "   git push -u origin main"
echo "6. Proceed to Phase 2 (Coolify Configuration), remembering to add BOTH passwords as Secrets."
echo "-----------------------------"
