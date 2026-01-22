FROM shandilya1998/nrt:pangolin

WORKDIR /deps

RUN apt-get update && apt-get install -y libepoxy-dev libjpeg-dev libtiff5-dev libpng-dev libcamera-tools libboost-dev openssl \
    libgnutls28-dev libgnutls28-dev qtbase5-dev libqt5core5a libqt5gui5 libqt5widgets5 libcap-dev libasio-dev ninja-build && \
    python3 -m pip install meson==1.8.2 jinja2 ninja==1.11.1.4 pybind11

RUN apt-get update && apt-get install -y gstreamer-1.0 \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-tools \
    gstreamer1.0-x \
    gstreamer1.0-alsa \
    gstreamer1.0-gl \
    gstreamer1.0-gtk3 \
    gstreamer1.0-qt5 \
    gstreamer1.0-pulseaudio

# Raspberry Pi specific dependencies
RUN if [ "$(uname -m)" = "aarch64" ]; then \
    apt-get update && apt-get install -y libraspberrypi-bin v4l-utils; \
    fi

WORKDIR /deps

RUN if [ "$(uname -m)" = "aarch64" ]; then \
    apt-get update && apt-get install -y rng-tools && \
    (rngd -r /dev/urandom -o /dev/random 2>/dev/null &) && \
    git clone https://github.com/raspberrypi/libcamera.git && \
    cd libcamera && \
    git checkout v0.5.0+rpt20250429 && \
    meson setup build --buildtype=release -Dpipelines=rpi/vc4,rpi/pisp -Dipas=rpi/vc4,rpi/pisp -Dv4l2=true -Dgstreamer=enabled -Dtest=false -Dlc-compliance=disabled -Dcam=disabled -Dqcam=disabled -Ddocumentation=disabled -Dpycamera=enabled -Dpython.bytecompile=-1 && \
    ninja -C build install; \
    elif [ "$(uname -m)" = "x86_64" ]; then \
    git clone https://github.com/libcamera-org/libcamera.git && \
    cd libcamera && \
    meson setup build --buildtype=release -Dv4l2=true -Dgstreamer=enabled -Dtest=false && \
    ninja -C build install; \
    fi	

RUN if [ "$(uname -m)" = "aarch64" ]; then \
    cd /deps && \
    git clone https://github.com/raspberrypi/rpicam-apps.git && \
    cd rpicam-apps && \
    git checkout 2437ab244390f222c814840b0132427ac3b13979 && \
    meson setup build -Denable_libav=enabled -Denable_drm=enabled -Denable_egl=enabled -Denable_qt=enabled -Denable_opencv=enabled -Denable_tflite=disabled && \
    meson compile -C build && \
    meson install -C build && \		
    ldconfig; \
    fi

# TODO check if python installation for rpi-libcamera and rpi-kms and picamera2 are required

RUN if [ "$(uname -m)" = "x86_64" ]; then \
    apt-get update && apt-get install -y ros-humble-octomap ros-humble-octomap-msgs ros-humble-octomap-msgs-dbgsym ros-humble-octomap-ros ros-humble-octomap-dbgsym ros-humble-octomap-server ros-humble-octomap-rviz-plugins ros-humble-octomap-rviz-plugins-dbgsym ros-humble-octomap-ros-dbgsym ros-humble-octomap-server-dbgsym ros-humble-octomap-mapping; \
    fi

RUN git clone https://github.com/flann-lib/flann.git && \
    cd flann && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make -j 16 && \
    make install

WORKDIR /ros_ws
COPY build_camera_ros.sh /ros_ws/
RUN ./build_camera_ros.sh 

RUN apt-get install -y rsync

WORKDIR /ws
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]
