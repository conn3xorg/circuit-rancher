# Local example

Builds a one-node k3s cluster with [circuit-k3s](https://github.com/conn3xorg/circuit-k3s) in a throwaway Rocky Linux 10 container, then installs Rancher on it. You need Conn3x and Podman. The container gets by on less memory than Rancher asks for in real use, which is fine for a look around.

k3s runs containers of its own, so the host container runs privileged, and rootless Podman can't give it the cpuset cgroup k3s needs. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The apply takes a few minutes, and the second plan says `No changes.` To check that Rancher answers, that you can log in with the bootstrap password, and that the local cluster is active:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 sh -s < check.sh
```

The container can't load kernel modules, so its host needs `br_netfilter` and `overlay` loaded. A Podman machine has both. On Linux, run `sudo modprobe -a br_netfilter overlay` first.

`up.sh` only forwards SSH, so Rancher's UI isn't reachable from your browser here. `check.sh` talks to it from inside the container. The example's password is a default in `main.tf`, which is fine for a container you're about to delete and nowhere else.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volume, the key and the state.
