FROM shandilya1998/nrt:camera


WORKDIR /ardu_ws/src
RUN apt-get update

COPY ./ros2.repos /ardu_ws/src/ros2.repos
RUN vcs import --recursive < ros2.repos && rm -rf /ardu_ws/src/ardupilot/Tools/ros2/ardupilot_sitl

ENV ROS_VERSION=2
ENV ROS_PYTHON_VERSION=3
ENV ROS_DISTRO=humble

WORKDIR /ardu_ws
# RUN rosdep update && \
# 	rosdep install --rosdistro ${ROS_DISTRO} --from-paths src

# RUN git clone -b master --recurse-submodules https://github.com/ArduPilot/Micro-XRCE-DDS-Gen.git --depth 1 --no-single-branch --branch master dds-gen \
#     && cd dds-gen \
#     && ./gradlew assemble
#
# RUN apt-get update && \
# 	apt-get install -y libxml2-dev \
#     	libxml2-utils \
# 		python3-lxml \
# 		python3-opencv \
# 		python3-wxgtk4.0 \
# 		python3-pip \
# 		python3-matplotlib \
# 		python3-pygame

RUN python3 -m pip install PyYAML mavproxy lxml --user && \
	echo 'export PATH="$PATH:$HOME/.local/bin"' >> /etc/profile

# ENV PATH="/ardu_ws/dds-gen/scripts:$PATH"

COPY ./build.sh /ardu_ws/build.sh
RUN chmod +x build.sh && ./build.sh

COPY ./ros_entrypoint.sh /
RUN chmod +x /ros_entrypoint.sh

WORKDIR /airsim_ws
ADD ./airsim_ws /airsim_ws
COPY ./build_airsim.sh /airsim_ws/build.sh
RUN apt-get install wget && chmod +x build.sh && ./build.sh

WORKDIR /ws

RUN apt-get update && apt-get install -y ros-humble-ffmpeg-image-transport

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
