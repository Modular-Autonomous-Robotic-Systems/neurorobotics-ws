#!/bin/bash

install_git=false
generate_ssh=false

while [[ $# -gt 0 ]]; do
    case "$1" in
    --git)
        install_git=true
        shift
        ;;
    --ssh)
        generate_ssh=true
        shift
        ;;
    --docker)
        install_docker=true
        shift
        ;;
    *)
        echo "Invalid option: $1"
        exit 1
        ;;
    esac
done

if [ "$install_git" = true ]; then
    echo "============ INSTALLING git ============="
    sudo apt-get update -y
    sudo apt-get install git -y
    echo ""
fi

if [ "$generate_ssh" = true ]; then
    echo "============ SETTING UP ssh ============="
    mkdir -p $HOME/.ssh
    ssh-keygen -o -t rsa -C "ssh@github.com" -f $HOME/.ssh/id_rsa
    echo ""
    echo "PUBLIC KEY:"
    echo ""
    cat $HOME/.ssh/id_rsa.pub
    echo ""
    echo "Copy and paste the above public key into your GitHub account. Refer: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account"
fi

if [ "$install_docker" = true ]; then
    # https://docs.docker.com/engine/install/ubuntu/
    echo "============ INSTALLING docker ============="
    sudo apt-get update -y
    sudo apt-get install curl git xclip -y
    echo ""

    # Install Docker using the convenience script
    curl -sSL https://get.docker.com | sh

    sudo usermod -aG docker ${USER}
    # Ensure the socket has the correct permissions
    if [ -e /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock
    fi

    echo "If 'docker info' gives permission denied error, you may have to reboot OS. https://stackoverflow.com/questions/47854463/#comment109932432_52646981"
fi
