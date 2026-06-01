FROM shandilya1998/nrt:camera

RUN apt-get update && apt-get install --no-install-recommends -y \
    lsb-release \
    gawk \
    wget \
    zip \
    default-jre \
    ros-humble-ffmpeg-image-transport \
    socat && \
    python3 -m pip install --no-cache-dir -U pexpect \
    pyelftools \
    tabulate \
    pymavlink \
    pre-commit \
    junitparser \
    empy==3.3.4 \
    libbz2-dev \
    future \
    lxml

WORKDIR /ardu_ws/src
RUN apt-get update

COPY ./ros2.repos /ardu_ws/src/ros2.repos
RUN vcs import --recursive < ros2.repos

RUN apt-get update && \
    python3 -m pip install mavproxy --user && \
    echo 'export PATH="$PATH:$HOME/.local/bin"' >> /etc/profile

ENV ROS_VERSION=2
ENV ROS_PYTHON_VERSION=3
ENV ROS_DISTRO=humble

WORKDIR /deps

RUN git clone -b master --recurse-submodules https://github.com/ArduPilot/Micro-XRCE-DDS-Gen.git --no-single-branch --branch master dds-gen \
    && cd dds-gen \
    && ./gradlew assemble

ARG ARM_ROOT="gcc-arm-none-eabi-10"
ARG ARM_ROOT_EXT="-2020-q4-major"
ARG ARM_TARBALL="$ARM_ROOT$ARM_ROOT_EXT-x86_64-linux.tar.bz2"
ARG ARM_TARBALL_URL="https://firmware.ardupilot.org/Tools/STM32-tools/$ARM_TARBALL"

WORKDIR /opt
RUN wget -qO- "$ARM_TARBALL_URL" | tar jx \
    && mv "/opt/$ARM_ROOT$ARM_ROOT_EXT" "/opt/$ARM_ROOT" \
    && rm -rf "/opt/$ARM_ROOT/share/doc"

# manual ccache setup for arm-none-eabi-g++/arm-none-eabi-gcc
RUN mkdir -p /usr/bin/ccache /usr/lib/ccache/ && \
    ln -s /usr/bin/ccache /usr/lib/ccache/arm-none-eabi-g++ \
    && ln -s /usr/bin/ccache /usr/lib/ccache/arm-none-eabi-gcc

# Set STM32 toolchain to the PATH
ENV PATH="/opt/$ARM_ROOT/bin:$PATH"

RUN mkdir -p $HOME/arm-gcc \
    && ln -s -f /opt/gcc-arm-none-eabi-10/ g++-10.2.1

ENV PATH="/deps/dds-gen/scripts:$PATH"
# Set ccache to the PATH
ENV PATH="/usr/lib/ccache:$PATH"

# Gain some time by disabling mavnative
ENV DISABLE_MAVNATIVE=True

# Set the buildlogs directory into /tmp as other directory aren't accessible
ENV BUILDLOGS=/tmp/buildlogs

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY ./build.sh /ardu_ws/build.sh
RUN chmod +x /ardu_ws/build.sh && /ardu_ws/build.sh

COPY ./ros_entrypoint.sh /
RUN chmod +x /ros_entrypoint.sh

WORKDIR /airsim_ws
RUN python3 -m pip install rpc-msgpack numpy && pip install --upgrade cosysairsim
ADD ./airsim_ws /airsim_ws
COPY ./build_airsim.sh /airsim_ws/build.sh
RUN chmod +x build.sh && ./build.sh

WORKDIR /ws

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
