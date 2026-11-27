echo "=== OS ==="
cat /etc/os-release 2>/dev/null | head -20
echo "=== CPU/MEM ==="
nproc; free -g | head -3
echo "=== DISK ==="
lsblk 2>/dev/null | head -20; df -h | head -20
echo "=== CONTAINER RUNTIME ==="
which docker podman nerdctl crictl k3s kubectl 2>/dev/null
docker version 2>/dev/null | head -8
podman --version 2>/dev/null
echo "=== SELINUX/FIREWALL ==="
getenforce 2>/dev/null; systemctl is-active firewalld 2>/dev/null
echo "=== NETWORK ==="
ip -4 addr show | grep -E "inet|^[0-9]" | head -20
ip route | head -5
cat /etc/resolv.conf 2>/dev/null | head -5
echo "=== INTERNET ==="
timeout 8 curl -sS -o /dev/null -w "docker.io:%{http_code}\n" https://registry-1.docker.io/v2/ 2>&1
timeout 8 curl -sS -o /dev/null -w "github:%{http_code}\n" https://github.com 2>&1
timeout 8 curl -sS -o /dev/null -w "mirrors.aliyun:%{http_code}\n" https://mirrors.aliyun.com 2>&1
echo "=== YUM REPO ==="
cat /etc/yum.repos.d/*.repo 2>/dev/null | grep -E "^\[|baseurl|enabled" | head -30
echo "=== PORTS ==="
ss -lntp 2>/dev/null | head -20
echo "=== INSTALLED KEY PKG ==="
rpm -q git curl wget tar jq 2>/dev/null
