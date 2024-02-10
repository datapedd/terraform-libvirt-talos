# About

[![Lint](https://github.com/rgl/terraform-libvirt-talos/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/terraform-libvirt-talos/actions/workflows/lint.yml)

An example [Talos Linux](https://www.talos.dev) Kubernetes cluster in libvirt QEMU/KVM Virtual Machines using terraform.

[Cilium](https://cilium.io) is used to augment the Networking (e.g. the [`LoadBalancer`](https://cilium.io/use-cases/load-balancer/) and [`Ingress`](https://docs.cilium.io/en/stable/network/servicemesh/ingress/) controllers), Observability (e.g. [Service Map](https://cilium.io/use-cases/service-map/)), and Security (e.g. [Network Policy](https://cilium.io/use-cases/network-policy/)).

# Usage (Ubuntu 22.04 host)

Install libvirt:

```bash
# install libvirt et al.
apt-get install -y virt-manager
# configure the security_driver to prevent errors alike (when using terraform):
#   Could not open '/var/lib/libvirt/images/terraform_talos_example_c0.img': Permission denied'
sed -i -E 's,#?(security_driver)\s*=.*,\1 = "none",g' /etc/libvirt/qemu.conf
systemctl restart libvirtd
# let the current user manage libvirtd.
# see /usr/share/polkit-1/rules.d/60-libvirt.rules
usermod -aG libvirt $USER
# restart the shell.
exit
```

Install Terraform:

```bash
wget https://releases.hashicorp.com/terraform/1.7.3/terraform_1.7.3_linux_amd64.zip
unzip terraform_1.7.3_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
```

Install cilium cli:

```bash
cilium_version='0.15.22'
cilium_url="https://github.com/cilium/cilium-cli/releases/download/v$cilium_version/cilium-linux-amd64.tar.gz"
wget -O- "$cilium_url" | tar xzf - cilium
sudo install cilium /usr/local/bin/cilium
rm cilium
```

Install cilium hubble:

```bash
hubble_version='0.13.0'
hubble_url="https://github.com/cilium/hubble/releases/download/v$hubble_version/hubble-linux-amd64.tar.gz"
wget -O- "$hubble_url" | tar xzf - hubble
sudo install hubble /usr/local/bin/hubble
rm hubble
```

Install talosctl:

```bash
talos_version='1.6.4'
wget https://github.com/siderolabs/talos/releases/download/v$talos_version/talosctl-linux-amd64
sudo install talosctl-linux-amd64 /usr/local/bin/talosctl
rm talosctl-linux-amd64
```

Install the talos image into libvirt, and initialize terraform:

```bash
./do init
```

Create the infrastructure:

```bash
time ./do plan-apply
```

Show talos information:

```bash
export TALOSCONFIG=$PWD/talosconfig.yml
controllers="$(terraform output -raw controllers)"
workers="$(terraform output -raw workers)"
all="$controllers,$workers"
c0="$(echo $controllers | cut -d , -f 1)"
talosctl -n $all version
talosctl -n $all dashboard
```

Show kubernetes information:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
kubectl cluster-info
kubectl get nodes -o wide
```

Show Cilium information:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
cilium status --wait
```

In another shell, open the Hubble UI:

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
cilium hubble ui
```

Execute an [example workload](https://github.com/rgl/example-docker-buildx-go):

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
kubectl apply -f example.yml
kubectl rollout status deployment/example
kubectl get ingresses,services,pods,deployments
example_ip="$(kubectl get ingress/example -o json | jq -r .status.loadBalancer.ingress[0].ip)"
example_fqdn="$(kubectl get ingress/example -o json | jq -r .spec.rules[0].host)"
example_url="http://$example_fqdn"
curl --resolve "$example_fqdn:80:$example_ip" "$example_url"
echo "$example_ip $example_fqdn" | sudo tee -a /etc/hosts
curl "$example_url"
xdg-open "$example_url"
kubectl delete -f example.yml
```

Execute an [example WebAssembly (Wasm) WasmEdge workload](https://github.com/rgl/wasmedge-http-rust-example):

```bash
export KUBECONFIG=$PWD/kubeconfig.yml
kubectl apply -f example-wasmedge.yml
kubectl rollout status deployment/example-wasmedge
kubectl get ingresses,services,pods,deployments
example_wasmedge_ip="$(kubectl get ingress/example-wasmedge -o json | jq -r .status.loadBalancer.ingress[0].ip)"
example_wasmedge_fqdn="$(kubectl get ingress/example-wasmedge -o json | jq -r .spec.rules[0].host)"
example_wasmedge_url="http://$example_wasmedge_fqdn"
curl --resolve "$example_wasmedge_fqdn:80:$example_wasmedge_ip" "$example_wasmedge_url"
echo "$example_wasmedge_ip $example_wasmedge_fqdn" | sudo tee -a /etc/hosts
curl "$example_wasmedge_url"
xdg-open "$example_wasmedge_url"
kubectl delete -f example-wasmedge.yml
```

Destroy the infrastructure:

```bash
time ./do destroy
```

# Troubleshoot

Talos:

```bash
# see https://www.talos.dev/v1.6/advanced/troubleshooting-control-plane/
talosctl -n $all support && rm -rf support && 7z x -osupport support.zip && code support
talosctl -n $c0 service ext-qemu-guest-agent status
talosctl -n $c0 service etcd status
talosctl -n $c0 etcd status
talosctl -n $c0 etcd alarm list
talosctl -n $c0 etcd members
talosctl -n $c0 get members
talosctl -n $c0 health --control-plane-nodes $controllers --worker-nodes $workers
talosctl -n $c0 inspect dependencies | dot -Tsvg >c0.svg && xdg-open c0.svg
talosctl -n $c0 dashboard
talosctl -n $c0 logs controller-runtime
talosctl -n $c0 logs kubelet
talosctl -n $c0 disks
talosctl -n $c0 mounts | sort
talosctl -n $c0 get resourcedefinitions
talosctl -n $c0 get machineconfigs -o yaml
talosctl -n $c0 get staticpods -o yaml
talosctl -n $c0 get staticpodstatus
talosctl -n $c0 get manifests
talosctl -n $c0 get services
talosctl -n $c0 get extensions
talosctl -n $c0 get addresses
talosctl -n $c0 get nodeaddresses
talosctl -n $c0 netstat --extend --programs --pods --listening
talosctl -n $c0 list -l -r -t f /etc
talosctl -n $c0 list -l -r -t f /system
talosctl -n $c0 list -l -r -t f /var
talosctl -n $c0 list -l -r /dev
talosctl -n $c0 list -l /sys/fs/cgroup
talosctl -n $c0 read /proc/cmdline | tr ' ' '\n'
talosctl -n $c0 read /proc/mounts | sort
talosctl -n $c0 read /etc/os-release
talosctl -n $c0 read /etc/resolv.conf
talosctl -n $c0 read /etc/containerd/config.toml
talosctl -n $c0 read /etc/cri/containerd.toml
talosctl -n $c0 read /etc/cri/conf.d/cri.toml
talosctl -n $c0 read /etc/kubernetes/kubelet.yaml
talosctl -n $c0 read /etc/kubernetes/kubeconfig-kubelet
talosctl -n $c0 read /etc/kubernetes/bootstrap-kubeconfig
talosctl -n $c0 ps
talosctl -n $c0 containers -k
```

Cilium:

```bash
cilium status --wait
cilium config view
cilium hubble ui
# **NB** cilium connectivity test is not working out-of-the-box in the default
# test namespaces and using it in kube-system namespace will leave garbage
# behind.
#cilium connectivity test --test-namespace kube-system
kubectl -n kube-system get leases | grep cilium-l2announce-
```

Kubernetes:

```bash
kubectl get events --all-namespaces --watch
kubectl --namespace kube-system get events --watch
kubectl --namespace kube-system debug node/w0 --stdin --tty --image=busybox:1.36 -- cat /host/etc/resolv.conf
kubectl --namespace kube-system get configmaps coredns --output yaml
pod_name="$(kubectl --namespace kube-system get pods --selector k8s-app=kube-dns --output json | jq -r '.items[0].metadata.name')"
kubectl --namespace kube-system debug $pod_name --stdin --tty --image=busybox:1.36 --target=coredns -- sh -c 'cat /proc/$(pgrep coredns)/root/etc/resolv.conf'
kubectl --namespace kube-system run busybox -it --rm --restart=Never --image=busybox:1.36 -- nslookup -type=a talos.dev
kubectl get crds
kubectl api-resources
```
