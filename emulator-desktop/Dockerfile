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
