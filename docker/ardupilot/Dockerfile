FROM shandilya1998/nrt_ardupilot:base

ARG DEBIAN_FRONTEND=noninteractive
ARG USER_NAME=ardupilot
ARG USER_UID=1000
ARG USER_GID=1000
ARG SKIP_AP_EXT_ENV=0
ARG SKIP_AP_GRAPHIC_ENV=1
ARG SKIP_AP_COV_ENV=1
ARG SKIP_AP_GIT_CHECK=1
ARG DO_AP_STM_ENV=1

RUN sudo apt-get update && sudo apt-get install -y libncurses-dev checkinstall cmake

RUN cd /home/${USER_NAME} && git clone https://github.com/vim/vim.git && cd vim && git checkout  6cc3027 && sudo ./configure --with-features=huge \
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

RUN mkdir -p /home/${USER_NAME}/.vim/bundle && \
	cd /home/${USER_NAME}/.vim/bundle && \
	git clone https://github.com/VundleVim/Vundle.vim && \
	mkdir -p /home/${USER_NAME}/.vim/colors
COPY ./.vimrc /home/${USER_NAME}/.vimrc
COPY ./codedark.vim /home/${USER_NAME}/.vim/colors/codedark.vim 
RUN vim -c PluginInstall -c qall && ls && \
	cd /home/${USER_NAME}/.vim/bundle/ && \
	rm -rf youcompleteme && \
	git clone https://github.com/ycm-core/YouCompleteMe youcompleteme && \
	python3 -m pip install regex && \
	cd /home/${USER_NAME}/.vim/bundle/youcompleteme && \
	git submodule update --init --recursive && \
	python3 ./install.py --force-sudo --clang-completer && \
	cp /home/${USER_NAME}/.vim/bundle/youcompleteme/third_party/ycmd/.ycm_extra_conf.py  /home/${USER_NAME}/.vim/

RUN apt-get install -y ros-humble-ffmpeg-image-transport

ENTRYPOINT ["/ardupilot_entrypoint.sh"]
CMD ["bash"]
