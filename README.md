# Installing pre-equisites

For docker based setup we need have docker, git and ssh on our system. And if you already have these on your system, You can directly jump to the [Docker NRT setup](#docker-nrt-setup). Also, These scripts have been tested on Ubuntu 20.04.

Set the following statements in your ~/.bashrc:
```
export NRT_WS=$HOME/neurorobotics-ws
export PATH=$PATH:$NRT_WS
```

**Run this command with desired options**

```
$ ./djinn install --docker --ssh --git
```
[Add](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account) the generated ssh key to your github account . You may have to reboot to make docker work.


# Docker NRT setup

This simply automates usual installation. It builds all required docker images and installs all dependency libraries, git
pulls all repos and builds them. Tested for Ubuntu 20.04. **BFX and its related dependencies must be manually placed within ext folder in the workspace**

To build Skynet only and Skynet-ROS Images and start their containers run:
```
$ ./djinn init docker
```

To build NRT only image and start the container:
```
$ ./djinn init docker nrt
```

To build Kalibr docker image and start the container:
```
$ ./djinn init docker kalibr
```

# Initialising NRT Docker Container and building inside Docker Container

- **Run `xhost +` command on laptop terminal (no inside docker). This allows Pangolin inside docker to connect host’s X server.**

- Run the following initialisation commands according to need:
    - To initialise **NRT** container: `./djinn up nrt`

- To build ORBSlam2, ORBSlam3, AKAZESlam, NRT and/or NRT-ROS run the following commands according to need:
    - To build all of the above: `./djinn build`
    - To build NRT: `./djinn build nrt`
- To build ArduPilot for deployment use the following command:
    - `djinn build ardupilt $board $configuration`
    - `board` takes the name of the target board. For instance, board name for SpeedyBee F405 Wing is `SpeedyBeeF405WING`.
    - `configuration` takes the robot configuration as input. The values may be one of `plane`, `copter`, `rover` etc. Refer to ArduPilot documentation [here](https://ardupilot.org/dev/docs/building-setup-linux.html#building-setup-linux) for more reference.

# Miscellaneous Commands

The following commands are also available through ./djinn:

- To run commands in any initialised docker container: `./djinn exec <Container Suffix> <Command>`
    - For instance to enter a bash shell in the SITL container run the following command: `./djinn exec nrt bash`

- To Shutdown all containers: `./djinn down`

- To list all active containers: `./djinn ps`
