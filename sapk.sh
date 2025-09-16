#!/bin/bash

# ==============================================================================
# HÀM VÀ CẤU HÌNH BAN ĐẦU
# ==============================================================================

# Hàm kiểm tra lỗi
check_command() {
    if [ $? -ne 0 ]; then
        echo "❌ Lỗi: Lệnh '$1' thất bại." >&2
        echo "Script đã dừng lại. Vui lòng kiểm tra lại log lỗi." >&2
        exit 1
    fi
}

# Tùy chọn tương tác ban đầu
echo "================================================="
echo "   Waydroid Ultimate Installer - Tùy Chỉnh Cấu Hình "
echo "================================================="
read -p "Nhập mật khẩu VNC bạn muốn sử dụng (mặc định: 999888): " VNC_PASS_CUSTOM
VNC_PASS=${VNC_PASS_CUSTOM:-"999888"}
echo "Mật khẩu VNC sẽ là: $VNC_PASS"

read -p "Nhập độ phân giải màn hình VNC (ví dụ: 1280x720, mặc định: 1280x720): " VNC_RES_CUSTOM
VNC_RES=${VNC_RES_CUSTOM:-"1280x720"}
echo "Độ phân giải VNC sẽ là: $VNC_RES"

# Cấu hình tĩnh
VNC_USER="vncuser"
VNC_DEPTH="24"
WAYDROID_IMG_VER="20240324"

# ==============================================================================
# QUÁ TRÌNH CÀI ĐẶT
# ==============================================================================

echo ""
echo "📦 Đang tiến hành cài đặt các gói cơ bản và phụ thuộc..."
sudo apt-get update
check_command "sudo apt-get update"
sudo apt-get install -y curl gnupg nano wget dbus lxc-utils unzip git python3-venv python3-pip libgl1-mesa-glx xterm x11-xserver-utils x11-utils xfce4 xfce4-goodies tightvncserver libgl1 libgles2 libgbm1 libegl1 mesa-utils libegl-mesa0 libglapi-mesa
check_command "sudo apt-get install"

echo ""
echo "🛠️ Đang thêm kho lưu trữ Waydroid..."
curl --proto '=https' --tlsv1.2 -sSf https://repo.waydro.id/waydroid.gpg | sudo tee /usr/share/keyrings/waydroid.gpg > /dev/null
check_command "curl gpg key"
echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ stable main" | sudo tee /etc/apt/sources.list.d/waydroid.list
check_command "add repo"
sudo apt-get update
check_command "sudo apt-get update (Waydroid repo)"

echo ""
echo "🤖 Đang cài đặt Waydroid và tải container GApps..."
sudo apt-get install -y waydroid
check_command "sudo apt-get install waydroid"
sudo waydroid init -s -i "https://sourceforge.net/projects/waydroid/files/images/GAPPS/waydroid_arm64_gapps_gb_18.1_${WAYDROID_IMG_VER}.zip/download" -f "https://sourceforge.net/projects/waydroid/files/images/Vendor/waydroid_vendor_extra_arm64_14.1_${WAYDROID_IMG_VER}.zip/download"
check_command "waydroid init"

echo ""
echo "🚀 Đang cài đặt Magisk (Root)..."
git clone https://github.com/casualsnek/waydroid_script.git
check_command "git clone"
cd waydroid_script
check_command "cd waydroid_script"
python3 -m venv venv
check_command "python3 -m venv"
source venv/bin/activate
check_command "source venv"
pip install -r requirements.txt
check_command "pip install"
sudo venv/bin/python3 main.py install magisk
check_command "sudo install magisk"
deactivate
cd ..
rm -rf waydroid_script
check_command "rm -rf waydroid_script"

echo ""
echo "🎨 Tối ưu hóa GPU và cấu hình Waydroid..."
sudo waydroid prop set persist.waydroid.composite_mode client
sudo waydroid prop set persist.waydroid.hw_composer false
check_command "optimize waydroid"

echo ""
echo "🖥️ Đang thiết lập VNC Server..."
sudo useradd -m -s /bin/bash $VNC_USER
check_command "useradd"
echo "$VNC_USER:$VNC_PASS" | sudo chpasswd
check_command "chpasswd"
sudo mkdir -p /home/$VNC_USER/.vnc
check_command "mkdir .vnc"
sudo chmod 700 /home/$VNC_USER/.vnc
check_command "chmod .vnc"
echo "$VNC_PASS" | vncpasswd -f > /home/$VNC_USER/.vnc/passwd
check_command "vncpasswd"
sudo chmod 600 /home/$VNC_USER/.vnc/passwd
check_command "chmod passwd"

echo ""
echo "⚙️ Đang tạo script khởi động VNC..."
sudo tee /home/$VNC_USER/.vnc/xstartup > /dev/null <<EOF
#!/bin/bash
xrdb \$HOME/.Xresources
startxfce4 &
(sleep 15 && waydroid show-full-ui) &
EOF
check_command "tee xstartup"
sudo chmod +x /home/$VNC_USER/.vnc/xstartup
check_command "chmod +x xstartup"
sudo chown -R $VNC_USER:$VNC_USER /home/$VNC_USER
check_command "chown user"

# Tạo dịch vụ Systemd cho Waydroid
echo ""
echo "🚀 Đang tạo dịch vụ Systemd cho Waydroid..."
sudo tee /etc/systemd/system/waydroid.service > /dev/null <<EOF
[Unit]
Description=Waydroid Container Service
After=network.target

[Service]
ExecStart=/usr/bin/waydroid session start
User=root
Group=root
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
check_command "tee waydroid service"
sudo systemctl daemon-reload
check_command "daemon-reload"
sudo systemctl enable waydroid.service
check_command "enable waydroid"
sudo systemctl start waydroid.service
check_command "start waydroid"

# Tạo dịch vụ Systemd cho VNC Server
echo ""
echo "🚀 Đang tạo dịch vụ Systemd cho VNC Server..."
sudo tee /etc/systemd/system/vncserver@.service > /dev/null <<EOF
[Unit]
Description=Start TightVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=/home/$VNC_USER

PIDFile=/home/$VNC_USER/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -geometry $VNC_RES -depth $VNC_DEPTH :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF
check_command "tee vnc service"
sudo systemctl daemon-reload
check_command "daemon-reload"
sudo systemctl enable vncserver@1.service
check_command "enable vnc"
sudo systemctl start vncserver@1.service
check_command "start vnc"

echo "✅ Cài đặt hoàn tất! Mọi thứ đã sẵn sàng."
echo "-------------------------------------------------"
echo "Để kết nối, hãy mở ứng dụng VNC Viewer trên điện thoại của bạn."
echo "Địa chỉ: Your_VPS_IP:5901"
echo "Mật khẩu: $VNC_PASS"
echo "Khi kết nối, Waydroid UI sẽ tự động bật lên trong vài giây."
