#!/bin/bash
echo "ver 1.0.5"
# Cài đặt thông tin của client
FRP_VERSION="0.60.0"
SERVER_IP="103.77.166.69"
LOCAL_PORT=8080  # Thay đổi thành cổng HTTP proxy
FRP_USER="duyhuynh"
FRP_PASS="Anhduy3112"
API_SERVER="http://103.77.166.69"

# Cài đặt các phụ thuộc cần thiết
apt-get install -y gcc make wget jq

# Cài đặt 3proxy từ mã nguồn
wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.3.tar.gz
tar -xvzf 0.9.3.tar.gz
cd 3proxy-0.9.3
make -f Makefile.Linux
sudo make install

# Sao chép file nhị phân vào thư mục hệ thống
sudo cp bin/3proxy /usr/local/bin/
cd ..

# Cấu hình 3proxy với HTTP Proxy
echo "Tạo file cấu hình 3proxy..."
cat <<EOT | sudo tee /etc/3proxy.cfg
nserver 8.8.8.8
nserver 8.8.4.4

# Đặt thông tin xác thực
users duyhuynh:CL:Anhduy3112

# Bật xác thực
auth strong

# Cho phép tất cả các kết nối
allow * 

# Cấu hình proxy HTTP
proxy -p8080
EOT

# Tạo file dịch vụ systemd cho 3proxy
echo "Tạo dịch vụ systemd cho 3proxy..."
cat <<EOT | sudo tee /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Service
After=network.target

[Service]
ExecStart=/usr/local/bin/3proxy /etc/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

# Khởi động và kích hoạt dịch vụ 3proxy
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
sudo systemctl start 3proxy

# Cài đặt FRP client
mkdir -p /usr/local/frp
cd /usr/local/frp
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
tar -xvzf frp_${FRP_VERSION}_linux_amd64.tar.gz
rm frp_${FRP_VERSION}_linux_amd64.tar.gz

# Lấy tên máy (hostname) từ file /opt/autorun
if [ -f "/opt/autorun" ]; then
    HOSTNAME=$(grep -oP '\d{4,5}(?=:localhost:22)' /opt/autorun)
else
    HOSTNAME=$(hostname)
fi

# Kiểm tra nếu không tìm được HOSTNAME
if [ -z "$HOSTNAME" ]; then
    echo "Không tìm thấy hostname trong /opt/autorun, sử dụng hostname mặc định."
    HOSTNAME=$(hostname)
fi

# Lấy danh sách các cổng đã sử dụng từ server qua file JSON
USED_PORTS=($(curl -s $API_SERVER/used_ports | jq -r '.used_ports[]'))

# Chọn cổng ngẫu nhiên từ 12000 đến 12100 nhưng không trùng với các cổng đã sử dụng
REMOTE_PORT=12000
for port in $(seq 12000 12100); do
  if [[ ! " ${USED_PORTS[*]} " =~ " ${port} " ]]; then
    REMOTE_PORT=$port
    break
  fi
done

if [[ "$REMOTE_PORT" -eq 12000 ]]; then
  echo "Tất cả các cổng từ 12000 đến 12100 đã được sử dụng."
  exit 1
fi

# Tạo file cấu hình frpc.toml
echo "Tạo file cấu hình frpc.toml..."
cat <<EOT > /usr/local/frp/frp_${FRP_VERSION}_linux_amd64/frpc.toml
[common]
server_addr = "$SERVER_IP"
server_port = 7000
tcp_mux = true
tcp_mux.keepalive_interval = 30

[$HOSTNAME]
type = http
local_port = $LOCAL_PORT
remote_port = $REMOTE_PORT
http_user = "$FRP_USER"
http_passwd = "$FRP_PASS"
EOT

# Tạo file dịch vụ systemd cho FRP client
echo "Tạo dịch vụ systemd cho FRP client..."
cat <<EOT | sudo tee /etc/systemd/system/frpc.service
[Unit]
Description=FRP Client Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'until ping -c1 103.77.166.69; do sleep 1; done; /usr/local/frp/frp_0.60.0_linux_amd64/frpc -c /usr/local/frp/frp_0.60.0_linux_amd64/frpc.toml'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOT

# Kích hoạt và khởi động dịch vụ FRP
sudo systemctl daemon-reload
sudo systemctl enable frpc
sudo systemctl start frpc

# Gửi thông tin client lên API server
echo "Gửi thông tin client lên server..."
curl -X POST $API_SERVER/client_data \
-H "Content-Type: application/json" \
-d '{
    "hostname": "'"$HOSTNAME"'",
    "remote_port": '"$REMOTE_PORT"',
    "local_port": '"$LOCAL_PORT"'
}'

echo "Thông tin client đã được gửi thành công!"
