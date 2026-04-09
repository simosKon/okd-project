# OKD 4.18 (SCOS) Consolidated Runbook - vSphere UPI (3 Masters + 1 Worker)

## 1. Scope
This runbook is a single consolidated guide for installing OKD 4.18 on nested vSphere using UPI (`platform: none`) with:
- 3 control-plane nodes (masters)
- 1 worker node
- HAProxy + DNS + ignition via `guestinfo.*`

Validated release in this lab:
- `4.18.0-okd-scos.10`

## 2. Topology and Addressing
Adjust values to your environment, but keep the architecture.

### Services
- DNS: `192.168.1.8`
- HAProxy VM: `192.168.1.15`

### OKD Nodes
- bootstrap: `192.168.1.30`
- master01: `192.168.1.31`
- master02: `192.168.1.32`
- master03: `192.168.1.33`
- worker01: `192.168.1.34`

### VIPs (secondary IPs on HAProxy NIC)
- API/API-INT VIP: `192.168.1.50`
- Ingress VIP: `192.168.1.51`

### Required FQDN Mapping
- `api.okd.lab.local` -> `192.168.1.50`
- `api-int.okd.lab.local` -> `192.168.1.50`
- `apps.okd.lab.local` -> `192.168.1.51`
- `*.apps.okd.lab.local` -> `192.168.1.51`

Critical rule:
- `api-int` must point to the final VIP from the start and must not change during install.

## 3. vSphere Prerequisites
For all OKD VMs:
- Secure Boot disabled
- `disk.EnableUUID = TRUE`
- `stealclock.enable = TRUE`
- all nodes/services on reachable L2/L3 network
- prefer local/vSAN storage (avoid slow NFS for control plane)

Snapshot policy:
- Allowed: snapshots before first boot
- Not allowed: snapshots/reverts after bootstrap starts

## 4. Tooling and Version Alignment
Use the same OKD tag for all artifacts (`openshift-install`, `oc/kubectl`, SCOS image metadata).

```bash
export OKD_VERSION=4.18.0-okd-scos.10

wget https://github.com/okd-project/okd/releases/download/$OKD_VERSION/openshift-client-linux-$OKD_VERSION.tar.gz
wget https://github.com/okd-project/okd/releases/download/$OKD_VERSION/openshift-install-linux-$OKD_VERSION.tar.gz

tar -xzf openshift-client-linux-$OKD_VERSION.tar.gz
tar -xzf openshift-install-linux-$OKD_VERSION.tar.gz
chmod +x oc kubectl openshift-install
```

Get authoritative SCOS stream metadata:

```bash
./openshift-install coreos print-stream-json > stream.json
jq -r '.architectures.x86_64.artifacts.vmware.formats.ova.disk.location' stream.json
```

## 5. install-config.yaml (3M + 1W)

```yaml
apiVersion: v1
baseDomain: lab.local
metadata:
  name: okd
compute:
- name: worker
  replicas: 1
controlPlane:
  name: master
  replicas: 3
platform:
  none: {}
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
  machineNetwork:
  - cidr: 192.168.1.0/24
sshKey: "<your-ssh-pub-key>"
pullSecret: '<your-pull-secret>'
```

Generate manifests and ignition:

```bash
./openshift-install create manifests --dir .
./openshift-install create ignition-configs --dir .
```

Expected outputs:
- `bootstrap.ign`
- `master.ign`
- `worker.ign`

Important:
- Because `platform: none` is used (no vSphere IPI integration), the installer does **not** create VMs automatically.
- You must create the `bootstrap`, `master01-03`, and `worker01` VMs manually in vSphere and apply the required advanced settings/ignition.
- For `platform: vsphere` (IPI), VM creation is automated by the installer.
- For `platform: vsphere` (IPI), ignition delivery/required VM settings are handled by installer automation; manual `guestinfo.ignition.config.*` injection is typically **not** required.

## 6. Ignition Injection (vSphere guestinfo)
Base64 encode ignition files:

```bash
base64 -w0 bootstrap.ign > bootstrap.64
base64 -w0 master.ign > master.64
base64 -w0 worker.ign > worker.64
```

Set advanced parameters:

Bootstrap VM:
- `guestinfo.ignition.config.data=<bootstrap.64>`
- `guestinfo.ignition.config.data.encoding=base64`

Master VMs:
- `guestinfo.ignition.config.data=<master.64>`
- `guestinfo.ignition.config.data.encoding=base64`

Worker VM:
- `guestinfo.ignition.config.data=<worker.64>`
- `guestinfo.ignition.config.data.encoding=base64`

Also on all nodes:
- `disk.EnableUUID=TRUE`
- `stealclock.enable=TRUE`

## 7. DNS Records (before bootstrap)

```dns
api.okd.lab.local        A 192.168.1.50
api-int.okd.lab.local    A 192.168.1.50
apps.okd.lab.local       A 192.168.1.51
*.apps.okd.lab.local     A 192.168.1.51

bootstrap.okd.lab.local  A 192.168.1.30
master01.okd.lab.local   A 192.168.1.31
master02.okd.lab.local   A 192.168.1.32
master03.okd.lab.local   A 192.168.1.33
worker01.okd.lab.local   A 192.168.1.34
```

## 8. HAProxy Configuration (3 Masters + 1 Worker)
Required ports:
- `6443/tcp` API
- `22623/tcp` MCS
- `80/tcp`, `443/tcp` Ingress

`/etc/haproxy/haproxy.cfg`:

```cfg
global
  log 127.0.0.1 local2
  maxconn 4000
  daemon

defaults
  log global
  mode tcp
  timeout connect 5000
  timeout client 50000
  timeout server 50000

frontend api
  bind 192.168.1.50:6443
  default_backend api_servers

backend api_servers
  balance roundrobin
  server bootstrap 192.168.1.30:6443 check
  server master01 192.168.1.31:6443 check
  server master02 192.168.1.32:6443 check
  server master03 192.168.1.33:6443 check

frontend api-int
  bind 192.168.1.50:22623
  default_backend api_int_servers

backend api_int_servers
  balance roundrobin
  server bootstrap 192.168.1.30:22623 check
  server master01 192.168.1.31:22623 check
  server master02 192.168.1.32:22623 check
  server master03 192.168.1.33:22623 check

frontend http
  bind 192.168.1.51:80
  default_backend ingress_http

backend ingress_http
  balance roundrobin
  server worker01 192.168.1.34:80 check

frontend https
  bind 192.168.1.51:443
  default_backend ingress_https

backend ingress_https
  balance roundrobin
  server worker01 192.168.1.34:443 check
```

After `bootstrap-complete`:
- remove bootstrap from `api_servers`
- remove bootstrap from `api_int_servers`
- reload HAProxy

## 9. Install Sequence
1. Prepare `install-config.yaml`.
2. Generate manifests and ignition.
3. Inject ignition into VM advanced settings.
4. Boot `bootstrap` first.
5. After ~2 minutes, boot `master01-03` and `worker01`.
6. Wait for bootstrap completion.
7. Remove bootstrap from HAProxy backends.
8. Complete installation and validate cluster health.

## 10. Monitoring and Validation
On bootstrap:

```bash
sudo systemctl status bootkube.service
sudo journalctl -b -f -u release-image.service -u bootkube.service
sudo crictl ps -a | egrep 'etcd|apiserver|scheduler|controller'
```

From install host:

```bash
export KUBECONFIG=./auth/kubeconfig
oc get nodes
oc get csr
oc get clusteroperators
oc get clusterversion
oc get ingresscontroller -n openshift-ingress-operator
```

## 11. Common Failure Points
- `api-int` not resolving to final VIP from the beginning
- HAProxy backend/port mismatch (`6443` vs `22623`)
- slow storage causing etcd/bootstrap instability
- snapshots/reverts after bootstrap starts
- temporary ingress probe failures during early bring-up

## 12. DHCP vs Static Recommendation
For lab repeatability:
- use DHCP reservations for bootstrap/master/worker MACs
- keep DNS records aligned with reserved IPs

This minimizes FCOS early-networking problems and speeds up rebuilds.


