FROM shandilya1998/nrt_ardupilot:dev-ros

WORKDIR /ardu_ws/src
RUN apt-get update

COPY ./ros2.repos /ardu_ws/src/ros2.repos
RUN vcs import --recursive < ros2.repos

ENV ROS_VERSION=2
ENV ROS_PYTHON_VERSION=3
ENV ROS_DISTRO=humble

WORKDIR /ardu_ws/
# RUN rosdep update && \
# 	rosdep install --rosdistro ${ROS_DISTRO} --from-paths src

COPY ./build.sh /ardu_ws/build.sh
RUN chmod +x build.sh && ./build.sh

COPY ./ros_entrypoint.sh /
RUN chmod +x /ros_entrypoint.sh

WORKDIR /ws

RUN apt-get update && \
	apt-get install -y	python3-opencv python3-wxgtk4.0 python3-pip python3-matplotlib python3-lxml python3-pygame && \
	python3 -m pip install PyYAML mavproxy --user && \
	echo 'export PATH="$PATH:$HOME/.local/bin"' >> /etc/profile

RUN sudo apt-get update && sudo apt-get install -y libncurses-dev checkinstall cmake

RUN cd /root && git clone https://github.com/vim/vim.git && cd vim && git checkout  6cc3027 && sudo ./configure --with-features=huge \
            --enable-multibyte \
            --enable-rubyinterp=yes \
            --enable-python3interp=yes \
            --with-python3-config-dir=$(python3-config --configdir) \
            --enable-perlinterp=yes \
            --enable-luainterp=yes \
            --enable-gui=gtk2 \
            --enable-cscope \
            --prefix=/usr/local && \
		sudo make VIMRUNTIMEDIR=/usr/local/share/vim/vim91 && \
		sudo checkinstall -y

RUN mkdir -p /root/.vim/bundle && \
	cd /root/.vim/bundle && \
	git clone https://github.com/VundleVim/Vundle.vim && \
	mkdir -p /root/.vim/colors
COPY ./.vimrc /root/.vimrc
COPY ./codedark.vim /root/.vim/colors/codedark.vim 
RUN vim -c PluginInstall -c qall && ls && \
	cd /root/.vim/bundle/ && \
	rm -rf youcompleteme && \
	git clone https://github.com/ycm-core/YouCompleteMe youcompleteme && \
	python3 -m pip install regex && \
	cd /root/.vim/bundle/youcompleteme && \
	git submodule update --init --recursive && \
	python3 ./install.py --force-sudo --clang-completer && \
	cp /root/.vim/bundle/youcompleteme/third_party/ycmd/.ycm_extra_conf.py  /root/.vim/


WORKDIR /airsim_ws
ADD ./airsim_ws /airsim_ws
COPY ./build_airsim.sh /airsim_ws/build.sh
RUN apt-get install -y zip unzip ros-humble-vision-opencv ros-humble-cv-bridge ros-humble-ffmpeg-image-transport && chmod +x build.sh && ./build.sh

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
