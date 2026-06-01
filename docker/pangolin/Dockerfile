FROM shandilya1998/nrt:ros 

WORKDIR /deps

RUN git config --global advice.detachedHead false && \
    git clone --recursive https://github.com/stevenlovegrove/Pangolin.git && \
    cd Pangolin && git checkout tags/v0.8 -b v0.8

# Build Pangolin
WORKDIR /deps/Pangolin/build
RUN cmake .. && \
    cmake --build . -j4 && \
    cmake --install .

WORKDIR /deps
RUN git clone --depth=1 --branch=v11.4.3 https://github.com/machinezone/IXWebSocket.git || true && \
    cd IXWebSocket && \
    mkdir -p build && \
    cd build && \
    cmake -DBUILD_SHARED_LIBS=ON -DUSE_ZLIB=1 -DUSE_TLS=1 -DUSE_WS=1 .. && \
    make -j8 && \
    make install


WORKDIR /ws
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]
