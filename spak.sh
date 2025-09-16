#!/bin/bash

# ===================================================================================
# Script Cài đặt TỰ ĐỘNG HOÁ HOÀN THIỆN (PRO) - Waydroid + Desktop + Web VNC
# Phiên bản: 3.0 - "Hoàn Thiện"
# Tác giả: Gemini (Google AI)
#
# TÍNH NĂNG MỚI:
#   - Truy cập trực tiếp qua Trình duyệt Web (không cần app VNC/SSH).
#   - Thư mục chia sẻ file tự động giữa VPS và Android.
#   - Đồng bộ Clipboard (Copy & Paste) giữa thiết bị và Android.
# ===================================================================================

# Dừng script ngay lập tức nếu có lỗi
set -e

# --- Biến Cấu Hình ---
### CẢNH BÁO BẢO MẬT: Mật khẩu "999888" RẤT YẾU. Hãy thay đổi nó sau khi cài đặt!
VNC_PASSWORD="999888"
export DEBIAN_FRONTEND=noninteractive

echo "===== [BƯỚC 1/9] Cập nhật hệ thống và cài đặt các gói cần thiết... ====="
sudo apt-get update
sudo apt-get upgrade -y
# Gói cần thiết: lxc, curl, gpg, xfce4, tigervnc, scrcpy, adb
# Gói nâng cấp: novnc (web client), websockify (proxy), autocutsel (clipboard)
sudo apt-get install -y curl gpg ca-certificates software-properties-common apt-transport-https lxc gnupg \
xfce4 xfce4-goodies tigervnc-standalone-server scrcpy adb novnc websockify autocutsel

echo "===== [BƯỚC 2/9] Thêm repo và cài đặt Waydroid... ====="
curl -sS https://downloads.waydro.id/repo/waydroid.gpg | sudo gpg --dearmor -o /usr/share/keyrings/waydroid.gpg
echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://downloads.waydro.id/repo/ jammy main" | sudo tee /etc/apt/sources.list.d/waydroid.list
sudo apt-get update
sudo apt-get install -y waydroid

echo "===== [BƯỚC 3/9] Khởi tạo Waydroid với Google Apps (có thể mất vài phút)... ====="
sudo waydroid init -s GAPPS
sudo systemctl enable --now waydroid-container

echo "===== [BƯỚC 4/9] Cấu hình TigerVNC Server với mật khẩu và Clipboard... ====="
mkdir -p ~/.vnc
echo $VNC_PASSWORD | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Thêm autocutsel vào file khởi động để đồng bộ clipboard
cat <<EOF > ~/.vnc/xstartup
#!/bin/bash
xrdb \$HOME/.Xresources
autocutsel -fork
startxfce4 &
EOF
chmod +x ~/.vnc/xstartup

vncserver :1
vncserver -kill :1
sleep 2
sed -i 's/localhost = "no"/localhost = "yes"/' ~/.vnc/config

echo "===== [BƯỚC 5/9] Tạo Thư mục Chia sẻ File giữa VPS và Android... ====="
SHARED_FOLDER="$HOME/waydroid_share"
mkdir -p "$SHARED_FOLDER"
# Cấu hình Waydroid để tự động mount thư mục này
# Xóa cấu hình cũ nếu có để tránh trùng lặp
sudo sed -i "s|$SHARED_FOLDER||g" /var/lib/waydroid/waydroid_shared_mounts
echo "$SHARED_FOLDER" | sudo tee -a /var/lib/waydroid/waydroid_shared_mounts
echo "Thư mục chia sẻ đã được tạo tại: $SHARED_FOLDER"

echo "===== [BƯỚC 6/9] Tạo dịch vụ tự động khởi động VNC và Scrcpy... ====="
cat <<EOF | sudo tee /etc/systemd/system/vnc-scrcpy.service
[Unit]
Description=Start VNC Server and Scrcpy for Waydroid
After=network.target waydroid-container.service
[Service]
Type=forking
User=${USER}
ExecStartPre=/bin/bash -c 'while ! waydroid status | grep -q "RUNNING"; do echo "Waiting for Waydroid container..."; sleep 3; done'
ExecStart=/usr/bin/vncserver :1 -localhost
ExecStartPost=/bin/bash -c 'DISPLAY=:1 scrcpy --always-on-top &'
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

echo "===== [BƯỚC 7/9] Tạo dịch vụ cho Truy cập Web (NoVNC)... ====="
cat <<EOF | sudo tee /etc/systemd/system/novnc.service
[Unit]
Description=Start noVNC WebSocket Proxy
After=vnc-scrcpy.service
Wants=vnc-scrcpy.service
[Service]
Type=simple
User=${USER}
ExecStart=/usr/bin/websockify -D --web=/usr/share/novnc/ 6901 localhost:5901
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

echo "===== [BƯỚC 8/9] Khởi động lại và kích hoạt tất cả dịch vụ... ====="
sudo systemctl daemon-reload
sudo systemctl enable --now vnc-scrcpy.service
sudo systemctl enable --now novnc.service

# Khởi động lại container để nhận thư mục chia sẻ
sudo systemctl restart waydroid-container

echo "===== [BƯỚC 9/9] Đang chờ Waydroid khởi động hoàn tất... ====="
sleep 15 # Chờ một chút để Waydroid container ổn định

echo ""
echo "=================================================================================="
echo "                CÀI ĐẶT PHIÊN BẢN PRO HOÀN TẤT!                                  "
echo "=================================================================================="
echo ""
echo "Mọi thứ đã được tự động hóa. Giờ bạn có thể truy cập Android từ bất kỳ đâu."
echo ""
echo "--- CÁCH TRUY CẬP DỄ NHẤT (QUA TRÌNH DUYỆT WEB) ---"
echo "1. Mở trình duyệt web trên iPhone, iPad hoặc máy tính (Safari, Chrome...)."
echo "2. Truy cập vào địa chỉ sau (thay IP_VPS_CUA_BAN bằng IP thật):"
echo "   http://\$(curl -s ifconfig.me):6901"
echo "3. Bấm 'Connect' và nhập mật khẩu VNC khi được hỏi."
echo "   Mật khẩu VNC của bạn là: $VNC_PASSWORD"
echo ""
echo "--- CÁCH SỬ DỤNG CÁC TÍNH NĂNG MỚI ---"
echo "-> Chia sẻ File: "
echo "   - Trên VPS: Tải file (ví dụ: myapp.apk) vào thư mục '$SHARED_FOLDER'."
echo "   - Trong Android: Mở ứng dụng 'Files', bạn sẽ thấy file đó trong thư mục 'Waydroid'."
echo "     (Đường dẫn đầy đủ: /storage/emulated/0/Waydroid/)"
echo ""
echo "-> Clipboard chung: "
echo "   - Chỉ cần copy text trên điện thoại của bạn và paste vào trong Android (và ngược lại)."
echo "   - Tính năng đã được tự động kích hoạt."
echo ""
